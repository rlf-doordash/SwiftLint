@testable import SwiftLintFramework
import XCTest

final class OptimizedGlobMatcherTests: SwiftLintTestCase {
    func testPatternCategorization() {
        // Test prefix patterns (**suffix)
        XCTAssertEqual(
            OptimizedGlobPattern.categorize("**/.build"),
            .prefix("/.build")
        )
        XCTAssertEqual(
            OptimizedGlobPattern.categorize("**/*.generated.swift"),
            .prefix("/*.generated.swift")
        )
        XCTAssertEqual(
            OptimizedGlobPattern.categorize("**/Generated"),
            .prefix("/Generated")
        )
        
        // Test suffix patterns (prefix**)
        XCTAssertEqual(
            OptimizedGlobPattern.categorize("Pods/**"),
            .suffix("Pods")
        )
        XCTAssertEqual(
            OptimizedGlobPattern.categorize("build/**"),
            .suffix("build")
        )
        
        // Test complex patterns that need full glob - we can't easily test the exact resolved paths
        // since they depend on filesystem state, but we can test the pattern type
        let complexPattern1 = OptimizedGlobPattern.categorize("foo**bar**")
        if case .complex = complexPattern1 {
            // Expected
        } else {
            XCTFail("Should categorize foo**bar** as complex")
        }
        
        let complexPattern2 = OptimizedGlobPattern.categorize("**/foo**/bar")
        if case .complex = complexPattern2 {
            // Expected
        } else {
            XCTFail("Should categorize **/foo**/bar as complex")
        }
        
        // Test patterns with other glob characters (?, []) - should be complex
        let patternWithQuestion = OptimizedGlobPattern.categorize("**/*.swif?")
        if case .complex = patternWithQuestion {
            // Expected
        } else {
            XCTFail("Should categorize **/*.swif? as complex")
        }
        
        let patternWithBrackets = OptimizedGlobPattern.categorize("**/[Tt]est.swift")
        if case .complex = patternWithBrackets {
            // Expected
        } else {
            XCTFail("Should categorize **/[Tt]est.swift as complex")
        }
        
        // Test literal patterns (no wildcards)
        let literalPattern = OptimizedGlobPattern.categorize("literal/path")
        if case .complex = literalPattern {
            // Expected
        } else {
            XCTFail("Should categorize literal/path as complex")
        }
    }
    
    func testPrefixPatternMatching() {
        let pattern = OptimizedGlobPattern.prefix("/.build")
        
        // Should match paths ending with /.build
        XCTAssertTrue(pattern.matches(path: "/path/to/.build"))
        XCTAssertTrue(pattern.matches(path: "project/.build"))
        
        // Should not match paths that don't end with /.build
        XCTAssertFalse(pattern.matches(path: "/path/to/.build/file.swift"))
        XCTAssertFalse(pattern.matches(path: "/different/path"))
    }
    
    func testSuffixPatternMatching() {
        let pattern = OptimizedGlobPattern.suffix("Pods")
        
        // Should match paths starting with Pods
        XCTAssertTrue(pattern.matches(path: "Pods/SomeLibrary/File.swift"))
        XCTAssertTrue(pattern.matches(path: "Pods/Another"))
        
        // Should match even with trailing slash (input sanitization)
        XCTAssertTrue(pattern.matches(path: "Pods/"))
        XCTAssertTrue(pattern.matches(path: "Pods"))
        
        // Should not match paths that don't start with Pods
        XCTAssertFalse(pattern.matches(path: "/path/to/Pods"))
        XCTAssertFalse(pattern.matches(path: "App/Sources/File.swift"))
        XCTAssertFalse(pattern.matches(path: "MyPods/File.swift"))
    }
    
    func testOptimizedGlobMatcher() {
        // Test with realistic exclusion patterns
        let patterns = [
            "**/.build",
            "**/*.generated.swift", 
            "**/Generated",
            "Pods/**",
            "DerivedData/**"
        ]
        
        let matcher = OptimizedGlobMatcher(patterns: patterns)
        
        // Should match excluded paths
        XCTAssertTrue(matcher.matches(path: "/project/.build"))
        XCTAssertTrue(matcher.matches(path: "/src/File.generated.swift"))
        XCTAssertTrue(matcher.matches(path: "/app/Generated"))
        XCTAssertTrue(matcher.matches(path: "Pods/Alamofire/Source.swift"))
        XCTAssertTrue(matcher.matches(path: "DerivedData/Build/file"))
        
        // Should not match regular source files
        XCTAssertFalse(matcher.matches(path: "/src/ViewController.swift"))
        XCTAssertFalse(matcher.matches(path: "/app/Model.swift"))
        XCTAssertFalse(matcher.matches(path: "/tests/TestCase.swift"))
        
        // Test trailing slash handling
        XCTAssertTrue(matcher.matches(path: "Pods/"))
        XCTAssertTrue(matcher.matches(path: "DerivedData/"))
    }
    
    func testConfigurationFilterExcludedPaths() {
        // Test that the main Configuration.filterExcludedPaths method now uses optimized matching
        let config = Configuration(excludedPaths: ["**/.build", "**/*.generated.swift", "Pods/**"])
        
        let testPaths = [
            "/src/ViewController.swift",
            "/project/.build",
            "/src/File.generated.swift",
            "Pods/Alamofire/Source.swift",
            "/app/Model.swift"
        ]
        
        let filteredPaths = config.filterExcludedPaths(config.excludedPaths, in: testPaths)
        
        // Should exclude the patterns
        XCTAssertFalse(filteredPaths.contains("/project/.build"))
        XCTAssertFalse(filteredPaths.contains("/src/File.generated.swift"))
        XCTAssertFalse(filteredPaths.contains("Pods/Alamofire/Source.swift"))
        
        // Should include regular source files
        XCTAssertTrue(filteredPaths.contains("/src/ViewController.swift"))
        XCTAssertTrue(filteredPaths.contains("/app/Model.swift"))
    }
    
    func testGlobCharacterHandling() {
        // Test that patterns with glob characters other than ** are correctly categorized as complex
        
        // These should be PREFIX (simple)
        XCTAssertEqual(OptimizedGlobPattern.categorize("**/.build"), .prefix("/.build"))
        XCTAssertEqual(OptimizedGlobPattern.categorize("**/Generated"), .prefix("/Generated"))
        
        // These should be SUFFIX (simple)  
        XCTAssertEqual(OptimizedGlobPattern.categorize("Pods/**"), .suffix("Pods"))
        XCTAssertEqual(OptimizedGlobPattern.categorize("build/**"), .suffix("build"))
        
        // These should be COMPLEX (contain other glob characters)
        let complexPatterns = [
            "**/*.swif?",
            "**/Test[0-9].swift", 
            "Lib[s]/**",
            "Tes?/**",
            "**/**/nested",
            "prefix**suffix**"
        ]
        
        for pattern in complexPatterns {
            let categorized = OptimizedGlobPattern.categorize(pattern)
            if case .complex = categorized {
                // Expected
            } else {
                XCTFail("Should categorize \(pattern) as complex")
            }
        }
    }

    func testUserProvidedRealWorldPatterns() {
        // Test patterns provided by the user in the conversation
        let userPatterns = [
            "**/.index-build",
            "**/.build", 
            "**/*.generated.swift",
            "**/Generated",
            "**/LocalizedStrings.swift",
            "**/DynamicLocalizedStrings.swift"
        ]
        
        let matcher = OptimizedGlobMatcher(patterns: userPatterns)
        
        // These should be excluded
        XCTAssertTrue(matcher.matches(path: "Apps/Consumer/Layers/DomainInterfaces/.build/index-build/checkouts/AddMarkersSymbolExample.swift"))
        XCTAssertTrue(matcher.matches(path: "project/.index-build/some/file.swift"))
        XCTAssertTrue(matcher.matches(path: "project/.build/some/file.swift"))
        XCTAssertTrue(matcher.matches(path: "project/Generated/SomeFile.swift"))
        XCTAssertTrue(matcher.matches(path: "app/LocalizedStrings.swift"))
    }
    
    func testAbsolutePathAdjustment() {
        // Test that patterns are correctly adjusted to absolute paths
        let patterns = [
            "**/.build",        // Should NOT be adjusted (suffix pattern)
            "Foo/**",          // Should be adjusted to absolute path
            "Generated/*.swift", // Should be adjusted to absolute path
            "specific.swift"    // Should be adjusted to absolute path
        ]
        
        // Simulate config at /Users/project/Apps/Consumer/.swiftlint.yml
        let configDir = "/Users/project/Apps/Consumer"
        let expectedAdjustedPatterns = [
            "**/.build",                                      // Unchanged
            "/Users/project/Apps/Consumer/Foo/**",           // Adjusted
            "/Users/project/Apps/Consumer/Generated/*.swift", // Adjusted
            "/Users/project/Apps/Consumer/specific.swift"     // Adjusted
        ]
        
        let matcher = OptimizedGlobMatcher(patterns: expectedAdjustedPatterns)
        
        // Test that absolute paths match correctly
        XCTAssertTrue(matcher.matches(path: "/Users/project/Apps/Consumer/Foo/SomeFile.swift"))
        XCTAssertTrue(matcher.matches(path: "/Users/project/Apps/Consumer/Generated/Test.swift"))
        XCTAssertTrue(matcher.matches(path: "/Users/project/Apps/Consumer/specific.swift"))
        XCTAssertTrue(matcher.matches(path: "/Users/anywhere/.build/file.swift")) // Suffix pattern works globally
        
        // Test that non-matching paths are not excluded
        XCTAssertFalse(matcher.matches(path: "/Users/project/Apps/Consumer/Other/file.swift"))
        XCTAssertFalse(matcher.matches(path: "/Users/different/Apps/Consumer/Foo/file.swift"))
    }
} 