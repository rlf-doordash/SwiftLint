//
//  ExcludeByCategorizedGlobStrategy.swift
//

class ExcludeByCategorizedGlobStrategy: ExcludeByStrategy, PartialSubPathExcluder {
    let excludeByCategorizedGlobs: [CategorizedGlobPattern]

    init(excludedPaths: [Configuration.ExcludePath]) {
        excludeByCategorizedGlobs = excludedPaths.map(CategorizedGlobPattern.categorize)
    }

    func filterExcludedPaths(in paths: [String]...) -> [String] {
        paths.flatMap { $0 }
            .filter { path in
                !excludeByCategorizedGlobs.matches(path: path)
            }
    }

    func isExcluded(path: String) -> Bool {
        excludeByCategorizedGlobs.matches(path: path)
    }
}
