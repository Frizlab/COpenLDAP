import Foundation
import System

import Logging



/** All the paths relevant to the build */
struct BuildPaths {
	
	let opensslXCFramework: FilePath
	
	/** Not really a path, but hella convenient to have here */
	let productName: String
	let dylibProductNameComponent: FilePath.Component
	let staticLibProductNameComponent: FilePath.Component
	let frameworkProductNameComponent: FilePath.Component
	
	let resultXCFrameworkStatic: FilePath
	let resultXCFrameworkDynamic: FilePath
	
	let resultPackageSwift: FilePath
	let resultXCFrameworkStaticArchive: FilePath
	let resultXCFrameworkDynamicArchive: FilePath
	
	let developerDir: FilePath
	
	let templatesDir: FilePath
	
	let workDir: FilePath
	let resultDir: FilePath
	let buildDir: FilePath
	
	/** Contains the extracted tarball, config’d and built. One dir per target. */
	let sourcesDir: FilePath
	/** The builds from the previous step are installed here. */
	let installsDir: FilePath
	/** The static libs must be made FAT. We put the FAT ones here. */
	let fatStaticDir: FilePath
	/** This contains extracted static libs, linked later to create the dylibs. */
	let libObjectsDir: FilePath
	/** The dylibs created from the `libObjectsDir`. */
	let dylibsDir: FilePath
	/** Contains the headers from Target merged into platform+sdk tuple for the
	 static framework.
	 
	 Sometimes the headers are not exactly the same between architectures, so we
	 have to merge them in order to get the correct headers all the time. Also
	 the headers have to be patched to be able to be used in an XCFramework. */
	let mergedStaticHeadersDir: FilePath
	/**
	 Contains the libs from previous step, but merged as one.
	 
	 We have to do this because xcodebuild does not do it automatically when
	 building an xcframework (this is understandable) and xcframeworks do not
	 support multiple libs. */
	let mergedFatStaticLibsDir: FilePath
	/** Contains the headers from Target merged into platform+sdk tuple for the
	 dynamic framework.
	 
	 Sometimes the headers are not exactly the same between architectures, so we
	 have to merge them in order to get the correct headers all the time. Also
	 the headers have to be patched to be able to be used in a Framework. */
	let mergedDynamicHeadersDir: FilePath
	/** Contains the libs from previous step, one per platform+sdk instead of one
	 per target (marged as FAT).
	 
	 We have to do this because xcodebuild does not do it automatically when
	 building an xcframework (this is understandable), and an xcframework
	 splits the underlying framework on platform+sdk, not platform+sdk+arch.
	 
	 - Note: For symetry with its static counterpart we name this variable
	 `mergedFatDynamicLibsDir`, but the dynamic libs are merged from the
	 extracted static libs directly into one lib, so the `merged` part of the
	 variable is not strictly relevant. */
	let mergedFatDynamicLibsDir: FilePath
	
	/** Contains the final frameworks from which the dynamic xcframework will be
	 built. */
	let finalFrameworksDir: FilePath
	/** Contains the final full static lib install (with headers) from which
	 the static xcframework will be built. */
	let finalStaticLibsAndHeadersDir: FilePath
	
	init(filesPath: FilePath, workdir: FilePath, resultdir: FilePath?, productName: String, opensslFramework: XCFrameworkDependencySource) throws {
		self.developerDir = try FilePath(
			Process.spawnAndGetOutput("/usr/bin/xcode-select", args: ["-print-path"]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
		)
		
		self.templatesDir = filesPath.appending("Templates")
		
		self.workDir = workdir
		self.resultDir = resultdir ?? workdir
		self.buildDir = self.workDir.appending("build")
		
		self.opensslXCFramework = self.workDir.appending(opensslFramework.xcframeworkName)
		
		/* Actual (full) validation would be a bit more complex than that */
		let productNameValid = (productName.first(where: { !$0.isASCII || (!$0.isLetter && !$0.isNumber && $0 != "_") }) == nil)
		guard
			productNameValid,
			let dylibProductNameComponent     = FilePath.Component("lib" + productName +         ".dylib"),           dylibProductNameComponent.kind == .regular,
			let staticLibProductNameComponent = FilePath.Component("lib" + productName +         ".a"),           staticLibProductNameComponent.kind == .regular,
			let frameworkProductNameComponent = FilePath.Component(        productName +         ".framework"),   frameworkProductNameComponent.kind == .regular,
			let staticXCFrameworkComponent    = FilePath.Component(        productName +  "-static.xcframework"),    staticXCFrameworkComponent.kind == .regular,
			let dynamicXCFrameworkComponent   = FilePath.Component(        productName + "-dynamic.xcframework"),   dynamicXCFrameworkComponent.kind == .regular
		else {
			struct InvalidProductName : Error {var productName: String}
			throw InvalidProductName(productName: productName)
		}
		
		self.productName = productName
		self.dylibProductNameComponent = dylibProductNameComponent
		self.staticLibProductNameComponent = staticLibProductNameComponent
		self.frameworkProductNameComponent = frameworkProductNameComponent
		self.resultXCFrameworkStatic  = self.resultDir.appending(staticXCFrameworkComponent)
		self.resultXCFrameworkDynamic = self.resultDir.appending(dynamicXCFrameworkComponent)
		
		self.resultPackageSwift = self.resultDir.appending("Package.swift")
		self.resultXCFrameworkStaticArchive  = self.resultDir.appending( staticXCFrameworkComponent.string + ".zip")
		self.resultXCFrameworkDynamicArchive = self.resultDir.appending(dynamicXCFrameworkComponent.string + ".zip")
		
		self.sourcesDir  = self.buildDir.appending("step1.sources-and-builds")
		self.installsDir = self.buildDir.appending("step2.installs")
		
		self.fatStaticDir  = self.buildDir.appending("step3.intermediate-derivatives/fat-static-libs")
		self.libObjectsDir = self.buildDir.appending("step3.intermediate-derivatives/lib-objects")
		self.dylibsDir     = self.buildDir.appending("step3.intermediate-derivatives/dylibs")
		
		self.mergedStaticHeadersDir  = self.buildDir.appending("step4.final-derivatives/static-headers")
		self.mergedDynamicHeadersDir = self.buildDir.appending("step4.final-derivatives/dynamic-headers")
		self.mergedFatStaticLibsDir  = self.buildDir.appending("step4.final-derivatives/static-libs")
		self.mergedFatDynamicLibsDir = self.buildDir.appending("step4.final-derivatives/dynamic-libs")
		
		self.finalFrameworksDir           = self.buildDir.appending("step5.final-frameworks-and-libs/frameworks")
		self.finalStaticLibsAndHeadersDir = self.buildDir.appending("step5.final-frameworks-and-libs/static-libs-and-headers")
	}
	
	func clean() throws {
		try Config.fm.ensureDirectoryDeleted(path: opensslXCFramework)
		try Config.fm.ensureDirectoryDeleted(path: buildDir)
		try Config.fm.ensureDirectoryDeleted(path: resultXCFrameworkStatic)
		try Config.fm.ensureDirectoryDeleted(path: resultXCFrameworkDynamic)
		
		try Config.fm.ensureFileDeleted(path: resultPackageSwift)
		try Config.fm.ensureFileDeleted(path: resultXCFrameworkStaticArchive)
		try Config.fm.ensureFileDeleted(path: resultXCFrameworkDynamicArchive)
	}
	
	func ensureAllDirectoriesExist() throws {
		try Config.fm.ensureDirectory(path: workDir)
		try Config.fm.ensureDirectory(path: resultDir)
		try Config.fm.ensureDirectory(path: buildDir)
		
		try Config.fm.ensureDirectory(path: sourcesDir)
		try Config.fm.ensureDirectory(path: installsDir)
		try Config.fm.ensureDirectory(path: fatStaticDir)
		try Config.fm.ensureDirectory(path: libObjectsDir)
		try Config.fm.ensureDirectory(path: dylibsDir)
		
		try Config.fm.ensureDirectory(path: mergedStaticHeadersDir)
		try Config.fm.ensureDirectory(path: mergedFatStaticLibsDir)
		try Config.fm.ensureDirectory(path: mergedDynamicHeadersDir)
		try Config.fm.ensureDirectory(path: mergedFatDynamicLibsDir)
		
		try Config.fm.ensureDirectory(path: finalFrameworksDir)
		try Config.fm.ensureDirectory(path: finalStaticLibsAndHeadersDir)
	}
	
	func sourceDir(for target: Target) -> FilePath {
		return sourcesDir.appending(target.pathComponent)
	}
	
	func installDir(for target: Target) -> FilePath {
		return installsDir.appending(target.pathComponent)
	}
	
	func libObjectsDir(for target: Target) -> FilePath {
		return libObjectsDir.appending(target.pathComponent)
	}
	
	func dylibsDir(for target: Target) -> FilePath {
		return dylibsDir.appending(target.pathComponent)
	}
	
}
