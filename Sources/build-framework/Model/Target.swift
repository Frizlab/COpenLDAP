import Foundation
import System

import ArgumentParser



struct Target : Hashable, ExpressibleByArgument, CustomStringConvertible {
	
	var sdk: String
	var platform: String
	var arch: String
	
	init(sdk: String, platform: String, arch: String) {
		self.sdk = sdk
		self.platform = platform
		self.arch = arch
	}
	
	init?(argument: String) {
		let components = argument.split(separator: "-", omittingEmptySubsequences: false)
		guard components.count == 3 else {return nil}
		guard components.first(where: { $0 == "" || $0.contains("/") }) == nil else {return nil}
		
		self.sdk      = String(components[0])
		self.platform = String(components[1])
		self.arch     = String(components[2])
	}
	
	init?(xcframeworkPlatform: String, xcframeworkPlatformVariant: String?, xcframeworkArch: String) {
		switch (xcframeworkPlatform, xcframeworkPlatformVariant) {
			case ("macos", nil):            self.init(sdk: "macOS",   platform: "macOS",             arch: xcframeworkArch)
			case ("ios", nil):              self.init(sdk: "iOS",     platform: "iOS",               arch: xcframeworkArch)
			case ("ios", "simulator"?):     self.init(sdk: "iOS",     platform: "iOS_Simulator",     arch: xcframeworkArch)
			case ("ios", "maccatalyst"?):   self.init(sdk: "iOS",     platform: "macOS",             arch: xcframeworkArch)
			case ("tvos", nil):             self.init(sdk: "tvOS",    platform: "tvOS",              arch: xcframeworkArch)
			case ("tvos", "simulator"?):    self.init(sdk: "tvOS",    platform: "tvOS_Simulator",    arch: xcframeworkArch)
			case ("watchos", nil):          self.init(sdk: "watchOS", platform: "watchOS",           arch: xcframeworkArch)
			case ("watchos", "simulator"?): self.init(sdk: "watchOS", platform: "watchOS_Simulator", arch: xcframeworkArch)
			default:
				return nil
		}
	}
	
	var pathComponent: FilePath.Component {
		/* The forced-unwrap is **not** fully safe! But it should be most of the
		 * time (protected when the Target is inited from an argument), so for
		 * once, we don’t care… */
		return FilePath.Component(openSSLConfigName)!
	}
	
	/** The name in the config file we provide to OpenSSL */
	var openSSLConfigName: String {
		/* We assume the sdk, platform and arch are valid (do not contain dashes). */
		return [sdk, platform, arch].joined(separator: "-")
	}
	
	var description: String {
		return openSSLConfigName
	}
	
}


extension Target {
	
	static func platformLegacyName(fromPlatform platform: String) -> String {
		switch platform {
			case "macOS":             return "MacOSX"
			case "iOS":               return "iPhoneOS"
			case "iOS_Simulator":     return "iPhoneSimulator"
			case "tvOS":              return "AppleTVOS"
			case "tvOS_Simulator":    return "AppleTVSimulator"
			case "watchOS":           return "WatchOS"
			case "watchOS_Simulator": return "WatchSimulator"
			default: return platform.replacingOccurrences(of: "_", with: "")
		}
	}
	
	var platformLegacyName: String {
		return Self.platformLegacyName(fromPlatform: platform)
	}
	
	static func platformVersionName(fromPlatform platform: String, sdk: String) -> String {
		switch (platform, sdk) {
			case ("macOS", "iOS"):         return "mac-catalyst"
			case ("macOS", _):             return "macos"
			case ("iOS", _):               return "ios"
			case ("iOS_Simulator", _):     return "ios-simulator"
			case ("tvOS", _):              return "tvos"
			case ("tvOS_Simulator", _):    return "tvos-simulator"
			case ("watchOS", _):           return "watchos"
			case ("watchOS_Simulator", _): return "watchos-simulator"
			default: return platform.lowercased().replacingOccurrences(of: "_", with: "-")
		}
	}
	
	var platformVersionName: String {
		return Self.platformVersionName(fromPlatform: platform, sdk: sdk)
	}
	
}
