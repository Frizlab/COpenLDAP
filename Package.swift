// swift-tools-version:5.3
import PackageDescription


/* Binary package definition for COpenLDAP. */

let package = Package(
	name: "COpenLDAP",
	products: [
		/* Sadly the line below does not work. The idea was to have a
		 * library where SPM chooses whether to take the dynamic or static
		 * version of the target, but it fails (Xcode 12B5044c). */
//		.library(name: "COpenLDAP", targets: ["COpenLDAP-static", "COpenLDAP-dynamic"]),
//		.library(name: "COpenLDAP-static", targets: ["COpenLDAP-static"]),
		.library(name: "COpenLDAP-dynamic", targets: ["COpenLDAP-dynamic"])
	],
	targets: [
//		.binaryTarget(name: "COpenLDAP-static", url: "https://github.com/xcode-actions/COpenLDAP/releases/download/2.5.5/COpenLDAP-static.xcframework.zip", checksum: "47949ae57db44e2f08fae2cb007d2b6d46ffb9d266a5f2b4a0180711f1985725"),
		.binaryTarget(name: "COpenLDAP-dynamic", url: "https://github.com/xcode-actions/COpenLDAP/releases/download/2.5.5/COpenLDAP-dynamic.xcframework.zip", checksum: "e1edaf6988193301bc8dbcbf61b193b99f94efa4a82eb5edb447a597e42f48bc")
	]
)
