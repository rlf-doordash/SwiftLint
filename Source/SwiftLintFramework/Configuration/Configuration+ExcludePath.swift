//
//  Configuration+ExcludePath.swift
//

public extension Configuration {
    struct ExcludePath: Equatable, Sendable, Hashable {
        var currentPath: String
        var originalExcludePath: String
        var originalConfigPath: String

        init(_ path: String, originalConfigPath: String) {
            self.currentPath = path
            self.originalExcludePath = path
            self.originalConfigPath = originalConfigPath
        }

        private init(currentPath: String, originalExcludePath: String, originalConfigPath: String) {
            self.currentPath = currentPath
            self.originalExcludePath = originalExcludePath
            self.originalConfigPath = originalConfigPath
        }

        /// In general, two excluded paths are consider equal if they resolve to the same pattern
        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.currentPath == rhs.currentPath
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(currentPath)
        }

        func makeExcludePath(relativeTo newBasePath: String, previousBasePath: String) -> Self {
            let newPath = currentPath.bridge()
                .absolutePathRepresentation(rootDirectory: previousBasePath).path(relativeTo: newBasePath)
            return Self(currentPath: newPath,
                        originalExcludePath: originalExcludePath,
                        originalConfigPath: originalConfigPath)
        }

        /// Helper method for making the path absolute based on a root directory
        func makeAbsolutePath(rootDirectory: String) -> Self {
            let newPath = currentPath.bridge().absolutePathRepresentation(rootDirectory: rootDirectory)
            return Self(currentPath: newPath,
                        originalExcludePath: originalExcludePath,
                        originalConfigPath: originalConfigPath)
        }

        /// Helper method for making the path relative to a new directory.
        /// The path must already be absolute to use this method
        func makeRelativeTo(rootDirectory: String) -> Self {
            let newPath = currentPath.path(relativeTo: rootDirectory)
            return Self(currentPath: newPath,
                        originalExcludePath: originalExcludePath,
                        originalConfigPath: originalConfigPath)
        }
    }
}

extension Collection where Element == Configuration.ExcludePath {
    func contains(_ element: String) -> Bool {
        self.contains { excludePath in
            excludePath.currentPath == element
        }
    }
}

extension Collection where Element == String {
    func contains(_ element: Configuration.ExcludePath) -> Bool {
        self.contains { iteratingPath in
            element.currentPath == iteratingPath
        }
    }
}
