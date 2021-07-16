import Foundation
import System



struct XCFrameworkDependency {
	
	let path: FilePath
	let frameworksName: String
	
	init(path: FilePath) throws {
		let plistData = try Data(contentsOf: path.appending("Info.plist").url)
		let plistObject = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
		guard let plistDic = plistObject as? [String: Any] else {
			struct XCFrameworkPlistUnexpectedFormat : Error {}
			throw XCFrameworkPlistUnexpectedFormat()
		}
		let packageType = plistDic["CFBundlePackageType"]
		guard packageType as? String == "XFWK" else {
			struct XCFrameworkPlistUnexpectedPackageType : Error {var packageType: Any?}
			throw XCFrameworkPlistUnexpectedPackageType(packageType: packageType)
		}
		let formatVersion = plistDic["XCFrameworkFormatVersion"]
		guard formatVersion as? String == "1.0" else {
			struct XCFrameworkPlistUnexpectedFormatVersion : Error {var version: Any?}
			throw XCFrameworkPlistUnexpectedFormatVersion(version: packageType)
		}
		guard let availableLibraries = plistDic["AvailableLibraries"] as? [[String: Any]] else {
			struct XCFrameworkPlistDoNotHaveRecognizedAvailableLibraries : Error {}
			throw XCFrameworkPlistDoNotHaveRecognizedAvailableLibraries()
		}
		if plistDic.count > 3 {
			Config.logger.warning("Unknown entries in XCFramework info: \(plistDic)")
		}
		
		var previousFrameworkName: String?
		var frameworksByTarget = [Target: FilePath]()
		for availableLibrary in availableLibraries {
			guard
				let libId = availableLibrary["LibraryIdentifier"] as? String,
				let libPath = (availableLibrary["LibraryPath"] as? String).flatMap({ FilePath($0) }),
				let supportedArchs = availableLibrary["SupportedArchitectures"] as? [String],
				let supportedPlatform = availableLibrary["SupportedPlatform"] as? String,
				let supportedPlatformVariant = availableLibrary["SupportedPlatformVariant"] as? String?
			else {
				struct InvalidLibraryDescription : Error {var library: [String: Any]}
				throw InvalidLibraryDescription(library: availableLibrary)
			}
			if availableLibrary.count > 5 {
				Config.logger.warning("Unknown entries in available library: \(availableLibrary)")
			}
			
			/* Retrieve lib name, and verify lib is a framework */
			guard libPath.extension == "framework" else {
				struct GotANonFrameworkLibInXCFramework : Error {var library: [String: Any]}
				throw GotANonFrameworkLibInXCFramework(library: availableLibrary)
			}
			/* TODO: Retrieve the Framework’s name properly (dig into the framework) */
			guard let frameworkName = libPath.stem else {
				struct GotLibsWithNoNameInXCFramework : Error {var library: [String: Any]}
				throw GotLibsWithNoNameInXCFramework(library: availableLibrary)
			}
			guard previousFrameworkName == nil || previousFrameworkName == frameworkName else {
				struct GotTwoLibsWithDifferentNamesInXCFramework : Error {var library: [String: Any]}
				throw GotTwoLibsWithDifferentNamesInXCFramework(library: availableLibrary)
			}
			previousFrameworkName = frameworkName
			
			/* Line below crashes so we workaround it */
//			let fullRelativePath = FilePath(libId).appending(libPath.components)
			let fullRelativePath = FilePath(libId).appending("/" + libPath.string)
			for supportedArch in supportedArchs {
				guard let target = Target(xcframeworkPlatform: supportedPlatform, xcframeworkPlatformVariant: supportedPlatformVariant, xcframeworkArch: supportedArch) else {
					struct UnknownXCFrameworkTargetForLib : Error {var library: [String: Any]}
					throw UnknownXCFrameworkTargetForLib(library: availableLibrary)
				}
				guard frameworksByTarget[target] == nil else {
					struct GotTwiceSameTargetInXCFramework : Error {var xcframeworkInfo: [String: Any]}
					throw GotTwiceSameTargetInXCFramework(xcframeworkInfo: plistDic)
				}
				frameworksByTarget[target] = fullRelativePath
			}
		}
		
		guard let frameworkName = previousFrameworkName else {
			struct NoLibrariesInXCFramework : Error {}
			throw NoLibrariesInXCFramework()
		}
		
		self.path = path
		self.frameworksName = frameworkName
		self.frameworksByTarget = frameworksByTarget
	}
	
	/** Returns an absolute path for the framework for the given target. */
	func frameworkPath(forTarget target: Target) -> FilePath? {
		/* Crashes (presumably) */
//		return frameworksByTarget[target].flatMap{ path.appending($0.components) }
		return frameworksByTarget[target].flatMap{ path.appending("/" + $0.string) }
	}
	
	/** Values are absolute paths, relative to the xcframework path. */
	private let frameworksByTarget: [Target: FilePath]
	
}
