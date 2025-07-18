//
//  ExcludeByCategorizedGlobStrategy+CategorizedGlobPattern.swift
//
import Foundation

extension ExcludeByCategorizedGlobStrategy {
    
    public struct CategorizedGlobPatternData {
        let pattern: String
        let configurationPath: String
        
        let pathForSuffix: String
        
        init(pattern: String, configurationPath: String) {
            self.pattern = pattern
            self.configurationPath = configurationPath
            self.pathForSuffix = pattern.bridge().absolutePathRepresentation(rootDirectory: configurationPath)
        }
    }
    
    /// Categorizes glob patterns for optimized matching
    enum CategorizedGlobPattern {
        /// Pattern like `**foo` - matches paths ending with "foo"
        case prefix(CategorizedGlobPatternData)
        /// Pattern like `foo**` - matches paths starting with "foo"
        case suffix(CategorizedGlobPatternData)
        /// Complex pattern resolved to concrete paths
        case complex([String])
        
        /// Creates a pattern from a glob string
        static func categorize(_ pattern: Configuration.ExcludePath) -> CategorizedGlobPattern {
            let globCharset = CharacterSet(charactersIn: "*?[]")
            let originalExcludePath = pattern.originalExcludePath
            
            // Check for simple prefix pattern: **suffix (where suffix contains no glob characters)
            // We use original because we want to avoid any prepended path for this configuration. This will happen for prefix case as well
            if originalExcludePath.hasPrefix("**") {
                let suffix = String(originalExcludePath.dropFirst(2))
                // Ensure the suffix contains no glob characters (only the ** at start should be present)
                if suffix.rangeOfCharacter(from: globCharset) == nil {
                    // Handle **/ prefix
                    let cleanSuffix = suffix.hasPrefix("/") ? String(suffix.dropFirst()) : suffix
                    let data = CategorizedGlobPatternData(pattern: cleanSuffix, configurationPath: pattern.originalConfigPath)
                    return .prefix(data)
                }
            }
            
            // Check for simple suffix pattern: prefix** (where prefix contains no glob characters)
            if originalExcludePath.hasSuffix("**") {
                let prefix = String(originalExcludePath.dropLast(2))
                // Ensure the prefix contains no glob characters (only the ** at end should be present)
                if prefix.rangeOfCharacter(from: globCharset) == nil {
                    // Handle /** suffix
                    let cleanPrefix = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
                    let data = CategorizedGlobPatternData(pattern: cleanPrefix, configurationPath: pattern.originalConfigPath)
                    return .suffix(data)
                }
            }
            
            // For complex patterns, resolve immediately
            return .complex(Glob.resolveGlob(pattern.currentPath))
        }
        
        /// Fast matching for categorized patterns
        func matches(path: String) -> Bool {
            switch self {
            case .prefix(let suffix):
                // Suffix must match and the file must exist relative to the configuration that created the rule
                return path.hasSuffix(suffix.pattern) && path.starts(with: suffix.configurationPath)
            case .suffix(let prefix):
                // Compare against the known absolute path
                return path.hasPrefix(prefix.pathForSuffix)
            case .complex(let resolvedPaths):
                return resolvedPaths.contains { resolvedPath in
                    path.hasPrefix(resolvedPath) || resolvedPath.hasPrefix(path)
                }
            }
        }
    }
}
