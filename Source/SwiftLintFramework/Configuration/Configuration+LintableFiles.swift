import Foundation

extension Configuration {
    public enum ExcludeBy {
        case prefix
        case globPattern([OptimizedGlobPattern])
    }

    // MARK: Lintable Paths
    /// Returns the files that can be linted by SwiftLint in the specified parent path.
    ///
    /// - parameter path:            The parent path in which to search for lintable files. Can be a directory or a
    ///                              file.
    /// - parameter forceExclude:    Whether or not excludes defined in this configuration should be applied even if
    ///                              `path` is an exact match.
    /// - parameter excludeByPrefix: Whether or not uses excluding by prefix algorithm.
    ///
    /// - returns: Files to lint.
    public func lintableFiles(inPath path: String,
                              forceExclude: Bool,
                              excludeBy: ExcludeBy) -> [SwiftLintFile] {
        lintablePaths(inPath: path, forceExclude: forceExclude, excludeBy: excludeBy)
            .parallelCompactMap {
                SwiftLintFile(pathDeferringReading: $0)
            }
    }

    /// Returns the paths for files that can be linted by SwiftLint in the specified parent path.
    ///
    /// - parameter path:            The parent path in which to search for lintable files. Can be a directory or a
    ///                              file.
    /// - parameter forceExclude:    Whether or not excludes defined in this configuration should be applied even if
    ///                              `path` is an exact match.
    /// - parameter excludeByPrefix: Whether or not uses excluding by prefix algorithm.
    /// - parameter fileManager:     The lintable file manager to use to search for lintable files.
    ///
    /// - returns: Paths for files to lint.
    internal func lintablePaths(
        inPath path: String,
        forceExclude: Bool,
        excludeBy: ExcludeBy,
        fileManager: some LintableFileManager = FileManager.default
    ) -> [String] {
        if fileManager.isFile(atPath: path) {
            if forceExclude {
                switch excludeBy {
                case .prefix:
                    return filterExcludedPathsByPrefix(in: [path.absolutePathStandardized()])
                case .globPattern(let patterns):
                    let absolutePath = path.absolutePathStandardized()
                    return patterns.matches(path: absolutePath) ? [] : [absolutePath]
                }
            }
            // If path is a file and we're not forcing excludes, skip filtering with excluded/included paths
            return [path]
        }

        // Use optimized traversal with early directory skipping when possible
        let useOptimizedTraversal = fileManager is FileManager && !excludedPaths.isEmpty
        
        let pathsForPath: [String]
        let includedPaths: [String]
        
        if useOptimizedTraversal, let fm = fileManager as? FileManager {
            if self.includedPaths.isEmpty {
                // No included paths specified - scan the input path
                pathsForPath = fm.optimizedFilesToLint(inPath: path, configuration: self)
                includedPaths = []
            } else {
                // Included paths specified - ignore input path, only scan included paths
                pathsForPath = []
                includedPaths = self.includedPaths
                    .flatMap(Glob.resolveGlob)
                    .parallelFlatMap { fm.optimizedFilesToLint(inPath: $0, configuration: self) }
            }
        } else {
            // Fallback to original approach
            pathsForPath = self.includedPaths.isEmpty ? fileManager.filesToLint(inPath: path, rootDirectory: nil) : []
            includedPaths = self.includedPaths
                .flatMap(Glob.resolveGlob)
                .parallelFlatMap { fileManager.filesToLint(inPath: $0, rootDirectory: rootDirectory) }
        }

        switch excludeBy {
        case .prefix:
            return filterExcludedPathsByPrefix(in: pathsForPath, includedPaths)
        case .globPattern(let patterns):
            // When using optimized traversal, files are already filtered, so return as-is
            if useOptimizedTraversal {
                return pathsForPath + includedPaths
            } else {
                return filterExcludedPaths(patterns, in: pathsForPath, includedPaths)
            }
        }
    }

    /// Returns an array of file paths after removing the excluded paths as defined by this configuration.
    ///
    /// This method now uses optimized pattern matching for better performance with common glob patterns.
    ///
    /// - parameter excludedPaths: The excluded path patterns to filter out.
    /// - parameter paths:         The input paths to filter.
    ///
    /// - returns: The input paths after removing the excluded paths.
    public func filterExcludedPaths(
        _ excludedPaths: [String],
        in paths: [String]...
    ) -> [String] {
        let allPaths = paths.flatMap { $0 }
        guard !excludedPaths.isEmpty else { return allPaths }
        
        // Use the optimized patterns for all exclusion patterns
        let optimizedPatterns = excludedPaths.map { OptimizedGlobPattern.categorize($0, configRootPath: rootDirectory) }
        return allPaths.filter { path in
            !optimizedPatterns.matches(path: path.absolutePathStandardized())
        }
    }

    /// Returns an array of file paths after removing the excluded paths using optimized glob patterns.
    ///
    /// - parameter patterns: The optimized glob patterns to use for exclusion.
    /// - parameter paths:    The input paths to filter.
    ///
    /// - returns: The input paths after removing the excluded paths.
    public func filterExcludedPaths(
        _ patterns: [OptimizedGlobPattern],
        in paths: [String]...
    ) -> [String] {
        let allPaths = paths.flatMap { $0 }
        return allPaths.filter { path in
            !patterns.matches(path: path.absolutePathStandardized())
        }
    }


    /// Returns the file paths that are excluded by this configuration using filtering by absolute path prefix.
    ///
    /// For cases when excluded directories contain many lintable files (e. g. Pods) it works faster than default
    /// algorithm `filterExcludedPaths`.
    ///
    /// - returns: The input paths after removing the excluded paths.
    public func filterExcludedPathsByPrefix(in paths: [String]...) -> [String] {
        let allPaths = paths.flatMap { $0 }
        let excludedPaths = self.excludedPaths
            .parallelFlatMap { @Sendable in Glob.resolveGlob($0) }
            .map { $0.absolutePathStandardized() }
        return allPaths.filter { path in
            !excludedPaths.contains { path.hasPrefix($0) }
        }
    }

    /// Returns the file paths that are excluded by this configuration after expanding them using the specified file
    /// manager.
    ///
    /// - parameter fileManager: The file manager to get child paths in a given parent location.
    ///
    /// - returns: The expanded excluded file paths.
    public func excludedPaths(fileManager: some LintableFileManager = FileManager.default) -> [String] {
        excludedPaths
            .flatMap(Glob.resolveGlob)
            .parallelFlatMap { fileManager.filesToLint(inPath: $0, rootDirectory: rootDirectory) }
    }
}
