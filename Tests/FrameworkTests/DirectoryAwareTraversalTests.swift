import XCTest
@testable import SwiftLintFramework

final class DirectoryAwareTraversalTests: XCTestCase {
    func testDirectorySkipping() {
        let fileManager = FileManager.default
        let tempDir = NSTemporaryDirectory().appending("swiftlint_directory_test_\(UUID().uuidString)")
        let tempDirURL = URL(fileURLWithPath: tempDir)
        
        do {
            try fileManager.createDirectory(at: tempDirURL, withIntermediateDirectories: true)
            
            // Create directory structure:
            // tempDir/
            // ├── src/
            // │   └── Model.swift
            // ├── .build/
            // │   ├── debug/
            // │   │   └── Generated.swift
            // │   └── release/
            // │       └── Generated.swift
            // └── tests/
            //     └── Test.swift
            
            let srcDir = tempDirURL.appendingPathComponent("src")
            let buildDir = tempDirURL.appendingPathComponent(".build")
            let debugDir = buildDir.appendingPathComponent("debug")
            let releaseDir = buildDir.appendingPathComponent("release")
            let testsDir = tempDirURL.appendingPathComponent("tests")
            
            try fileManager.createDirectory(at: srcDir, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: buildDir, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: debugDir, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: releaseDir, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: testsDir, withIntermediateDirectories: true)
            
            // Create files
            try "// Source file".write(to: srcDir.appendingPathComponent("Model.swift"), atomically: true, encoding: .utf8)
            try "// Generated debug".write(to: debugDir.appendingPathComponent("Generated.swift"), atomically: true, encoding: .utf8)
            try "// Generated release".write(to: releaseDir.appendingPathComponent("Generated.swift"), atomically: true, encoding: .utf8)
            try "// Test file".write(to: testsDir.appendingPathComponent("Test.swift"), atomically: true, encoding: .utf8)
            
            // Test without exclusions - should find all 4 files
            let allFiles = fileManager.filesToLint(inPath: tempDir, rootDirectory: nil, excludeRegex: nil)
            XCTAssertEqual(allFiles.count, 4, "Should find all 4 Swift files")
            
            // Test with .build directory exclusion - should skip entire .build directory
            let regexMatcher = RegexMatcher(patterns: [".*\\.build/.*"])
            let filteredFiles = fileManager.filesToLint(inPath: tempDir, rootDirectory: nil, excludeRegex: regexMatcher)
            
            // Should only find files outside .build directory
            XCTAssertEqual(filteredFiles.count, 2, "Should find only 2 files after excluding .build directory")
            
            // Verify the correct files were found
            let filenames = filteredFiles.map { URL(fileURLWithPath: $0).lastPathComponent }
            XCTAssertTrue(filenames.contains("Model.swift"))
            XCTAssertTrue(filenames.contains("Test.swift"))
            XCTAssertFalse(filenames.contains("Generated.swift"))
            
            // Clean up
            try fileManager.removeItem(at: tempDirURL)
        } catch {
            XCTFail("Failed to create test directory structure: \(error)")
        }
    }
    
    func testMultipleDirectoryExclusions() {
        let fileManager = FileManager.default
        let tempDir = NSTemporaryDirectory().appending("swiftlint_multi_test_\(UUID().uuidString)")
        let tempDirURL = URL(fileURLWithPath: tempDir)
        
        do {
            try fileManager.createDirectory(at: tempDirURL, withIntermediateDirectories: true)
            
            // Create structure with multiple excluded directories
            let dirs = ["src", ".build", "Generated", "vendor"]
            for dir in dirs {
                let dirURL = tempDirURL.appendingPathComponent(dir)
                try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
                try "// File in \(dir)".write(to: dirURL.appendingPathComponent("File.swift"), atomically: true, encoding: .utf8)
            }
            
            // Exclude multiple patterns
            let regexMatcher = RegexMatcher(patterns: [
                ".*\\.build/.*",    // Exclude .build directory
                ".*Generated/.*",   // Exclude Generated directory
                ".*vendor/.*"       // Exclude vendor directory
            ])
            
            let filteredFiles = fileManager.filesToLint(inPath: tempDir, rootDirectory: nil, excludeRegex: regexMatcher)
            
            // Should only find the src file
            XCTAssertEqual(filteredFiles.count, 1, "Should find only 1 file after multiple exclusions")
            
            let filename = URL(fileURLWithPath: filteredFiles.first!).lastPathComponent
            XCTAssertEqual(filename, "File.swift")
            XCTAssertTrue(filteredFiles.first!.contains("/src/"))
            
            // Clean up
            try fileManager.removeItem(at: tempDirURL)
        } catch {
            XCTFail("Failed to create test directory structure: \(error)")
        }
    }
    
    func testPerformanceImprovement() {
        // This test demonstrates the performance benefit but doesn't assert specific timing
        // since that would be flaky in CI environments
        
        let fileManager = FileManager.default
        let tempDir = NSTemporaryDirectory().appending("swiftlint_perf_test_\(UUID().uuidString)")
        let tempDirURL = URL(fileURLWithPath: tempDir)
        
        do {
            try fileManager.createDirectory(at: tempDirURL, withIntermediateDirectories: true)
            
            // Create a large excluded directory with many files
            let buildDir = tempDirURL.appendingPathComponent(".build")
            try fileManager.createDirectory(at: buildDir, withIntermediateDirectories: true)
            
            // Create many files in .build directory
            for i in 0..<50 {
                let subdir = buildDir.appendingPathComponent("subdir\(i)")
                try fileManager.createDirectory(at: subdir, withIntermediateDirectories: true)
                try "// Generated \(i)".write(to: subdir.appendingPathComponent("Generated\(i).swift"), atomically: true, encoding: .utf8)
            }
            
            // Create one file outside .build
            try "// Source".write(to: tempDirURL.appendingPathComponent("Source.swift"), atomically: true, encoding: .utf8)
            
            let regexMatcher = RegexMatcher(patterns: [".*\\.build/.*"])
            
            let startTime = Date()
            let filteredFiles = fileManager.filesToLint(inPath: tempDir, rootDirectory: nil, excludeRegex: regexMatcher)
            let optimizedTime = Date().timeIntervalSince(startTime)
            
            // Should find only the source file, skipping all 50 files in .build
            XCTAssertEqual(filteredFiles.count, 1, "Should find only 1 file, skipping entire .build directory")
            XCTAssertTrue(filteredFiles.first!.hasSuffix("Source.swift"))
            
            // The optimization should be reasonably fast (this is more of a sanity check)
            XCTAssertLessThan(optimizedTime, 1.0, "Directory skipping should be fast")
            
            print("Directory-aware traversal found \(filteredFiles.count) files in \(String(format: "%.3f", optimizedTime)) seconds")
            print("✅ Successfully skipped 50 files in .build directory!")
            
            // Clean up
            try fileManager.removeItem(at: tempDirURL)
        } catch {
            XCTFail("Failed to create test directory structure: \(error)")
        }
    }
} 