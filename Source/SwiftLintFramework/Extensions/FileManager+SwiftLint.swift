import Foundation

/// An interface for enumerating files that can be linted by SwiftLint.
public protocol LintableFileManager {
    /// Returns all files that can be linted in the specified path. If the path is relative, it will be appended to the
    /// specified root path, or current working directory if no root directory is specified.
    /// This method will call subpaths in the file system to compute the result
    ///
    /// - parameter path:          The path in which lintable files should be found.
    /// - parameter rootDirectory: The parent directory for the specified path. If none is provided, the current working
    ///                            directory will be used.
    ///
    /// - returns: Files to lint.
    func filesToLint(inPath path: String, rootDirectory: String?) -> [String]

    /// Returns all files that can be linted in the specified path. If the path is relative, it will be appended to the
    /// specified root path, or current working directory if no root directory is specified.
    /// This method will discover directories iteratively one by one early skipping when possible
    ///
    /// - parameter path:          The path in which lintable files should be found.
    /// - parameter rootDirectory: The parent directory for the specified path. If none is provided, the current working
    ///                            directory will be used.
    /// - parameter excluder:      The excluder to check if any discovered directory should be early skipped
    ///
    /// - returns: Files to lint.
    func filesToLint(inPath path: String, rootDirectory: String?, excluder: any PartialSubPathExcluder) -> [String]

    /// Returns the date when the file at the specified path was last modified. Returns `nil` if the file cannot be
    /// found or its last modification date cannot be determined.
    ///
    /// - parameter path: The file whose modification date should be determined.
    ///
    /// - returns: A date, if one was determined.
    func modificationDate(forFileAtPath path: String) -> Date?

    /// Returns true if a file (but not a directory) exists at the specified path.
    ///
    /// - parameter path: The path that should be checked to see if it is a file.
    ///
    /// - returns: true if the specified path is a file.
    func isFile(atPath path: String) -> Bool
}

extension FileManager: LintableFileManager {
    public func filesToLint(inPath path: String, rootDirectory: String? = nil) -> [String] {
        let absolutePath = path.bridge()
            .absolutePathRepresentation(rootDirectory: rootDirectory ?? currentDirectoryPath).bridge()
            .standardizingPath

        // if path is a file, it won't be returned in `enumerator(atPath:)`
        if absolutePath.bridge().isSwiftFile(), absolutePath.isFile {
            return [absolutePath]
        }

        return subpaths(atPath: absolutePath)?.parallelCompactMap { element -> String? in
            guard element.bridge().isSwiftFile() else { return nil }
            let absoluteElementPath = absolutePath.bridge().appendingPathComponent(element)
            return absoluteElementPath.isFile ? absoluteElementPath : nil
        } ?? []
    }

    public func filesToLint(inPath path: String,
                            rootDirectory: String? = nil,
                            excluder: any PartialSubPathExcluder) -> [String] {
        let initialAbsolutePath = path.bridge()
            .absolutePathRepresentation(rootDirectory: rootDirectory ?? currentDirectoryPath).bridge()
            .standardizingPath

        var result: [String] = []
        var directoriesToProcess: [String] = [initialAbsolutePath]

        while !directoriesToProcess.isEmpty {
            let currentDirectory = directoriesToProcess.removeFirst()

            // Get immediate contents of current directory only (not recursive)
            guard let contents = try? contentsOfDirectory(atPath: currentDirectory) else {
                continue
            }

            for item in contents {
                let itemPath = currentDirectory.bridge().appendingPathComponent(item)

                var isDirectory: ObjCBool = false
                guard fileExists(atPath: itemPath, isDirectory: &isDirectory) else {
                    continue
                }

                let isSwiftFile = item.bridge().isSwiftFile()

                // Skip non-Swift files that aren't directories
                if !isSwiftFile, !isDirectory.boolValue {
                    continue
                }

                // Use the file-specific configuration's optimized matcher
                if excluder.isExcluded(path: itemPath) {
                    continue
                }

                if isSwiftFile {
                    // Add Swift file to results
                    result.append(itemPath)
                } else if isDirectory.boolValue {
                    // Add directory for future processing
                    directoriesToProcess.append(itemPath)
                }
            }
        }

        return result
    }

    public func modificationDate(forFileAtPath path: String) -> Date? {
        (try? attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    public func isFile(atPath path: String) -> Bool {
        path.isFile
    }
}
