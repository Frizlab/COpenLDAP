import CryptoKit
import Foundation
import System

import Logging



struct XCFrameworkDependency {
	
	let url: URL
	var expectedShasum: String?
	
	var skipExistingArtifacts: Bool
	
	/** The name of the tarball without the extensions, except for xcframework.
	 Usually the name of the folder inside the tarball. */
	let xcframeworkName: String
	
	init(url: URL, expectedShasum: String?, skipExistingArtifacts: Bool) throws {
		guard Set(arrayLiteral: "http", "https", "file").contains(url.scheme) else {
			struct UnknownXCFrameworkURLScheme : Error {var url: URL}
			throw UnknownXCFrameworkURLScheme(url: url)
		}
		guard let xcframeworkPathComponent = FilePath.Component(url.lastPathComponent) else {
			struct XCFrameworkURLIsWeird : Error {var url: URL}
			throw XCFrameworkURLIsWeird(url: url)
		}
		
		self.url = url
		self.expectedShasum = expectedShasum
		
		self.skipExistingArtifacts = skipExistingArtifacts
		
		/* Let’s compute the XCFramework name (always remove extension until we
		 * find xcframework or there are none left; if no extension is left we add
		 * xcframework). */
		var component = xcframeworkPathComponent
		while component.extension != "xcframework", let newComponent = FilePath.Component(component.stem), newComponent != component {
			component = newComponent
		}
		if component.extension != "xcframework" {
			assert(component.extension == nil)
			self.xcframeworkName = component.string + ".xcframework"
		} else {
			self.xcframeworkName = component.string
		}
	}
	
	/* The xcframework location will be destinationFolder.appending(xcframeworkName) */
	func downloadAndExtract(in destinationFolder: FilePath) async throws {
		let destPath = destinationFolder.appending(xcframeworkName)
		struct SourceXCFrameworkDoesNotExist : Error {}
		
		/* First check if source and destination are the same. */
		guard !url.isFileURL || url.path != destPath.string else {
			var isDir = ObjCBool(false)
			guard Config.fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
				throw SourceXCFrameworkDoesNotExist()
			}
			guard isDir.boolValue else {
				struct SourceAndDestXCFrameworkIsAFile : Error {}
				throw SourceAndDestXCFrameworkIsAFile()
			}
			/* If the source URL points to the destination and the destination
			 * exists and is a folder, we are done. */
			return
		}
		
		/* If they are not, do we need to do something? */
		guard !skipExistingArtifacts || !Config.fm.fileExists(atPath: destPath.string) else {
			Config.logger.info("Skipping creation of \(destPath) because it already exists")
			return
		}
		try Config.fm.ensureDirectory(path: destinationFolder)
		try Config.fm.ensureDirectoryDeleted(path: destPath)
		
		/* Now we know something must be done. Let’s do it! */
		let fileURL: URL
		let deleteSourceFile: Bool
		if !url.isFileURL {
			/* The source URL is not a file URL. Let’s download the file.
			 * Note: We could probably download a file URL (providing the file URL
			 * points to a file and not a directory), but we avoid some overhead
			 * when not doing that, and most importantly, we’d have to check the
			 * file URL does not point to a folder anyway. */
			Config.logger.info("Downloading XCFramework dependency from URL \(url)")
			let (tmpFileURL, urlResponse) = try await URLSession.shared.download(from: url, delegate: nil)
			guard let httpURLResponse = urlResponse as? HTTPURLResponse, 200..<300 ~= httpURLResponse.statusCode else {
				struct InvalidURLResponse : Error {var response: URLResponse}
				throw InvalidURLResponse(response: urlResponse)
			}
			fileURL = tmpFileURL
			deleteSourceFile = true
		} else {
			fileURL = url
			deleteSourceFile = false
		}
		
		/* We now have a file URL; first let’s get a FilePath instead. */
		guard let sourcePath = FilePath(fileURL) else {
			struct InternalError : Error {let message = "Cannot convert file URL path to FilePath"}
			throw InternalError()
		}
		/* When we’re done, we delete the source if needed */
		defer {
			if deleteSourceFile {_ = try? Config.fm.ensureFileDeleted(path: sourcePath)}
		}
		/* Now does the source path exist, and is it a file a directory? If it is
		 * a file we have an archive that must be unarchived, otherwise we
		 * consider the source is the xcframework and we copy it. */
		var isDir = ObjCBool(false)
		guard Config.fm.fileExists(atPath: sourcePath.string, isDirectory: &isDir) else {
			throw SourceXCFrameworkDoesNotExist()
		}
		if isDir.boolValue {
			/* Let’s copy the source to the destination */
			Config.logger.info("Copying XCFramework dependency from \(sourcePath.string)")
			try Config.fm.copyItem(atPath: sourcePath.string, toPath: destPath.string)
		} else {
			/* Let’s unarchive the source to the destination after checking for
			 * integrity. */
			guard try checkShasum(path: sourcePath) else {
				struct InvalidChecksum : Error {}
				throw InvalidChecksum()
			}
			Config.logger.info("Unarchiving XCFramework URL from \(sourcePath.string)")
			try Process.spawnAndStreamEnsuringSuccess("/usr/bin/ditto", args: ["-xk", sourcePath.string, destinationFolder.string], outputHandler: Process.logProcessOutputFactory())
		}
		guard Config.fm.fileExists(atPath: destPath.string, isDirectory: &isDir), isDir.boolValue else {
			struct ExtractedArchiveNotFound : Error {var expectedPath: FilePath}
			throw ExtractedArchiveNotFound(expectedPath: destPath)
		}
	}
	
	private func checkShasum(path: FilePath) throws -> Bool {
		guard let expectedShasum = expectedShasum else {
			return true
		}
		
		let fileContents = try Data(contentsOf: path.url)
		return SHA256.hash(data: fileContents).reduce("", { $0 + String(format: "%02x", $1) }) == expectedShasum.lowercased()
	}
	
}
