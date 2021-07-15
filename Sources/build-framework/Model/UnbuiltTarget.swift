import Foundation
import System

import Logging



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
