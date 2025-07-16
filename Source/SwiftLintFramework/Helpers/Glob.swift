import Foundation

#if os(Linux)
#if canImport(Glibc)
import func Glibc.glob
#elseif canImport(Musl)
import func Musl.glob
#endif
#endif

// MARK: - Optimized Pattern Matching

/// Categorizes glob patterns for optimized matching
public enum OptimizedGlobPattern: Equatable, Hashable {
    /// Pattern like `**foo` - matches paths ending with "foo"
    case prefix(String)
    /// Pattern like `foo**` - matches paths starting with "foo"
    case suffix(String)
    /// Complex pattern resolved to concrete paths
    case complex([String])
    
    /// Creates an optimized pattern from a glob string
    static func categorize(_ pattern: String, configRootPath: String) -> OptimizedGlobPattern {
        let globCharset = CharacterSet(charactersIn: "*?[]")
        
        // Simple patterns without glob characters are treated as literal
        guard pattern.rangeOfCharacter(from: globCharset) != nil else {
            return .complex(Glob.resolveGlob(pattern))
        }
        
        // Check for simple prefix pattern: **suffix (where suffix contains no glob characters)
        if pattern.hasPrefix("**") {
            let suffix = String(pattern.dropFirst(2))
            // Ensure the suffix contains no glob characters (only the ** at start should be present)
            if suffix.rangeOfCharacter(from: globCharset) == nil {
                // Handle **/ prefix
                let cleanSuffix = suffix.hasPrefix("/") ? String(suffix.dropFirst()) : suffix
                return .prefix(cleanSuffix)
            }
        }
        
        // Check for simple suffix pattern: prefix** (where prefix contains no glob characters)
        if pattern.hasSuffix("**") {
            let prefix = String(pattern.dropLast(2))
            // Ensure the prefix contains no glob characters (only the ** at end should be present)
            if prefix.rangeOfCharacter(from: globCharset) == nil {
                // Handle /** suffix  
                let cleanPrefix = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
                // Suffix patterns are always made absolute with the provided config root path
                let absolutePrefix = configRootPath.bridge().appendingPathComponent(cleanPrefix).absolutePathStandardized()
                return .suffix(absolutePrefix)
            }
        }
        
        // For complex patterns, resolve immediately
        return .complex(Glob.resolveGlob(pattern))
    }
    
    /// Fast matching for categorized patterns
    func matches(path: String) -> Bool {
        switch self {
        case .prefix(let suffix):
            return path.hasSuffix(suffix)
        case .suffix(let prefix):
            // Sanitize input path by removing trailing slash for consistent matching
            let cleanPath = path.hasSuffix("/") ? String(path.dropLast()) : path
            return cleanPath.hasPrefix(prefix)
        case .complex(let resolvedPaths):
            return resolvedPaths.contains { resolvedPath in
                path.hasPrefix(resolvedPath) || resolvedPath.hasPrefix(path)
            }
        }
    }
}

extension Sequence where Element == OptimizedGlobPattern {
    /// Fast path matching using string operations where possible
    func matches(path: String) -> Bool {
        for pattern in self {
            if pattern.matches(path: path) {
                return true
            }
        }
        return false
    }
}

// Adapted from https://gist.github.com/efirestone/ce01ae109e08772647eb061b3bb387c3

struct Glob {
    static func resolveGlob(_ pattern: String) -> [String] {
        let globCharset = CharacterSet(charactersIn: "*?[]")
        guard pattern.rangeOfCharacter(from: globCharset) != nil else {
            return [pattern]
        }

        return expandGlobstar(pattern: pattern)
            .reduce(into: [String]()) { paths, pattern in
                var globResult = glob_t()
                defer { globfree(&globResult) }

                #if canImport(Musl)
                let flags = GLOB_TILDE | GLOB_MARK
                #else
                let flags = GLOB_TILDE | GLOB_BRACE | GLOB_MARK
                #endif
                if glob(pattern, flags, nil, &globResult) == 0 {
                    paths.append(contentsOf: populateFiles(globResult: globResult))
                }
            }
            .unique
            .sorted()
            .map { $0.absolutePathStandardized() }
    }

    // MARK: Private

    private static func expandGlobstar(pattern: String) -> [String] {
        guard pattern.contains("**") else {
            return [pattern]
        }
        var parts = pattern.components(separatedBy: "**")
        let firstPart = parts.removeFirst()
        let fileManager = FileManager.default
        guard firstPart.isEmpty || fileManager.fileExists(atPath: firstPart) else {
            return []
        }
        let searchPath = firstPart.isEmpty ? fileManager.currentDirectoryPath : firstPart
        var directories = [String]()
        do {
            directories = try fileManager.subpathsOfDirectory(atPath: searchPath).compactMap { subpath in
                let fullPath = firstPart.bridge().appendingPathComponent(subpath)
                guard isDirectory(path: fullPath) else { return nil }
                return fullPath
            }
        } catch {
            Issue.genericWarning("Error parsing file system item: \(error)").print()
        }

        // Check the base directory for the glob star as well.
        directories.insert(firstPart, at: 0)

        var lastPart = parts.joined(separator: "**")
        var results = [String]()

        // Include the globstar root directory ("dir/") in a pattern like "dir/**" or "dir/**/"
        if lastPart.isEmpty {
            results.append(firstPart)
            lastPart = "*"
        }

        for directory in directories {
            let partiallyResolvedPattern: String
            if directory.isEmpty {
                partiallyResolvedPattern = lastPart.starts(with: "/") ? String(lastPart.dropFirst()) : lastPart
            } else {
                partiallyResolvedPattern = directory.bridge().appendingPathComponent(lastPart)
            }
            results.append(contentsOf: expandGlobstar(pattern: partiallyResolvedPattern))
        }

        return results
    }

    private static func isDirectory(path: String) -> Bool {
        var isDirectoryBool = ObjCBool(false)
        let isDirectory = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectoryBool)
        return isDirectory && isDirectoryBool.boolValue
    }

    private static func populateFiles(globResult: glob_t) -> [String] {
#if os(Linux)
        let matchCount = globResult.gl_pathc
#else
        let matchCount = globResult.gl_matchc
#endif
        return (0..<Int(matchCount)).compactMap { index in
            globResult.gl_pathv[index].flatMap { String(validatingUTF8: $0) }
        }
    }
}
