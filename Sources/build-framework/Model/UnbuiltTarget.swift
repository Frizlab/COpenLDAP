import Foundation
import System

import Logging


/* ********* Build “algo” *********
 *
 * Replace "\bopenssl/" with "COpenSSL/"
 * Patch libraries/liblutil/Makefile.in: Remove detach.* from UNIX_OBJS and UNIX_SRCS
 *    -> This is because it uses fork which is not available on iOS and other mobile OSes
 *       (fork is only used for the server code which we do not care about.)
 *
 * XCT_DEV_DIR=`/usr/bin/xcode-select -print-path`
 * XCT_SDKs_LOCATION=$XCT_DEV_DIR/Platforms/${target.platformLegacyName}.platform/Developer
 * XCT_SDK=${target.platformLegacyName}${sdk_version}.sdk
 * XCT_OPENSSL_FRAMEWORK_PATH=.../COpenSSL-dynamic.xcframework/macos-arm64_x86_64
 * XCT_COMMON_FLAGS="-isysroot $XCT_SDKs_LOCATION/SDKs/$XCT_SDK -fembed-bitcode -fno-common -fPIC -F$XCT_OPENSSL_FRAMEWORK_PATH"
 *   -fno-common -> idk what that is, but from what I gather it’s related to the fact we want static libs convertible to dylibs
 *
 * export CPPFLAGS="$XCT_COMMON_FLAGS"
 * export LDFLAGS="$XCT_COMMON_FLAGS -framework COpenSSL -Wl,-rpath -Wl,$XCT_OPENSSL_FRAMEWORK_PATH"
 * ./configure --prefix=".../openldap-workdir-2.5.5/build/step2.installs/macOS-macOS-arm64"
 * make depend && make -C libraries && make -C libraries install
 *
 * TODO: Min SDK options (trivial from OpenSSL confs)
 *
 * Bitcode seems to only appear in .a products for whatever reason, but we don’t care, we rebuild the dylib from the .a
 *
 * To compile for $ARCH
 *   - Add "-arch $ARCH" to XCT_COMMON_FLAGS
 *   - Add "--host $HOST --with-yielding_select=yes" to configure
 *   - Hosts (note I’m not 100% certain of this list, e.g. what version of darwin should be used, etc.):
 *        - macOS-x86_64:      x86_64-apple-darwin21.0.0
 *        - macOS-arm64:      aarch64-apple-darwin21.0.0
 *        - watchOS-arm64_32:     arm-apple-darwin21.0.0
 *
 * Untested and not very useful because we rebuild dylibs from static ones, but should work:
 *   install_name_tool -delete_rpath $XCT_OPENSSL_FRAMEWORK_PATH $LIB.dylib
 */

struct UnbuiltTarget {
	
	var target: Target
	var tarball: Tarball
	var buildPaths: BuildPaths
	
	var sdkVersion: String?
	var minSDKVersion: String?
	var openldapVersion: String
	
	var disableBitcode: Bool
	
	var skipExistingArtifacts: Bool
	
	func buildTarget() throws -> BuiltTarget {
		let sourceDir = buildPaths.sourceDir(for: target)
		let installDir = buildPaths.installDir(for: target)
		try extractTarballBuildAndInstallIfNeeded(installDir: installDir, sourceDir: sourceDir)
		
		let (headers, staticLibs) = try retrieveArtifacts()
		return BuiltTarget(target: target, sourceFolder: sourceDir, installFolder: installDir, staticLibraries: staticLibs, dynamicLibraries: [], headers: headers, resources: [])
	}
	
	private func extractTarballBuildAndInstallIfNeeded(installDir: FilePath, sourceDir: FilePath) throws {
		guard !skipExistingArtifacts || !Config.fm.fileExists(atPath: installDir.string) else {
			Config.logger.info("Skipping building of target \(target) because \(installDir) exists")
			return
		}
		
		/* ********* SOURCE EXTRACTION ********* */
		
		/* Extract tarball in source directory. If the tarball was already there,
		 * tar will overwrite existing files (but will not remove additional
		 * files). */
		let extractedTarballDir = try tarball.extract(in: sourceDir)
		
		/* ********* BUILD & INSTALL ********* */
		
		Config.logger.info("Building for target \(target)")
		
		/* Apparently we *have to* change the CWD (though we should do it through
		 * Process which has an API for that). */
		let previousCwd = Config.fm.currentDirectoryPath
		Config.fm.changeCurrentDirectoryPath(extractedTarballDir.string)
		defer {Config.fm.changeCurrentDirectoryPath(previousCwd)}
		
		/* Prepare -j option for make */
		let multicoreMakeOption = Self.numberOfCores.flatMap{ ["-j", "\($0)"] } ?? []
		
		/* *** Configure *** */
		guard
			let platformPathComponent = FilePath.Component(target.platformLegacyName + ".platform"),
			let sdkPathComponent = FilePath.Component(target.platformLegacyName + (sdkVersion ?? "") + ".sdk")
		else {
			struct InternalError : Error {}
			throw InternalError()
		}
		let configArgs = [
			"--prefix=\(installDir.string)"
		]
		struct NotImplemented : Error {}
		throw NotImplemented()
		try Process.spawnAndStreamEnsuringSuccess(extractedTarballDir.appending("configure").string, args: configArgs, outputHandler: Process.logProcessOutputFactory())
		
		/* *** Build *** */
		try Process.spawnAndStreamEnsuringSuccess("/usr/bin/xcrun", args: ["make"] + multicoreMakeOption, outputHandler: Process.logProcessOutputFactory())
		
		/* *** Install *** */
		try Process.spawnAndStreamEnsuringSuccess("/usr/bin/xcrun", args: ["make", "install_sw"] + multicoreMakeOption, outputHandler: Process.logProcessOutputFactory())
	}
	
	private func retrieveArtifacts() throws -> (headers: [FilePath], staticLibs: [FilePath]) {
		let installDir = buildPaths.installDir(for: target)
		let exclusions = try [
			NSRegularExpression(pattern: #"^\.DS_Store$"#, options: []),
			NSRegularExpression(pattern: #"/\.DS_Store$"#, options: [])
		]
		
		var headers = [FilePath]()
		var staticLibs = [FilePath]()
		try Config.fm.iterateFiles(in: installDir, exclude: exclusions, handler: { fullPath, relativePath, isDir in
			func checkFileLocation(expectedLocation: FilePath, fileType: String) {
				if !relativePath.starts(with: expectedLocation) {
					Config.logger.warning("found \(fileType) at unexpected location: \(relativePath)", metadata: ["target": "\(target)", "path_root": "\(installDir)"])
				}
			}
			
			switch (isDir, fullPath.extension) {
				case (true, _): (/*nop*/)
					
				case (false, "a"):
					/* We found a static lib. Let’s check its location and add it. */
					checkFileLocation(expectedLocation: "lib", fileType: "lib")
					staticLibs.append(relativePath)
					
				case (false, "h"):
					/* We found a header lib. Let’s check its location and add it. */
					checkFileLocation(expectedLocation: "include/openssl", fileType: "header")
					headers.append(relativePath)
					
				case (false, nil):
					/* Binary. We don’t care about binaries. But let’s check it is
					 * at an expected location. */
					checkFileLocation(expectedLocation: "bin", fileType: "binary")
					
				case (false, "pc"):
					/* pkgconfig file. We don’t care about those. But let’s check
					 * this one is at an expected location. */
					checkFileLocation(expectedLocation: "lib/pkgconfig", fileType: "pc file")
					
				case (false, _):
					Config.logger.warning("found unknown file: \(relativePath)", metadata: ["target": "\(target)", "path_root": "\(installDir)"])
			}
			return true
		})
		return (headers, staticLibs)
	}
	
	private static var numberOfCores: Int? = {
		guard MemoryLayout<Int32>.size <= MemoryLayout<Int>.size else {
			Config.logger.notice("Int32 is bigger than Int (\(MemoryLayout<Int32>.size) > \(MemoryLayout<Int>.size)). Cannot return the number of cores.")
			return nil
		}
		
		var ncpu: Int32 = 0
		var len = MemoryLayout.size(ofValue: ncpu)
		
		var mib = [CTL_HW, HW_NCPU]
		let namelen = u_int(mib.count)
		
		guard sysctl(&mib, namelen, &ncpu, &len, nil, 0) == 0 else {return nil}
		return Int(ncpu)
	}()
	
}
