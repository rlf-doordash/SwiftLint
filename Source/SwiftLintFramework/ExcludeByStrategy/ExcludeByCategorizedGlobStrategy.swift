//
//  ExcludeByCategorizedGlobStrategy.swift
//

class ExcludeByCategorizedGlobStrategy: ExcludeByStrategy {
    
    let excludeByCategorizedGlobs: [CategorizedGlobPattern]
    
    init(excludedPaths: [Configuration.ExcludePath]) {
        excludeByCategorizedGlobs = excludedPaths.map (CategorizedGlobPattern.categorize)
    }
    
    func filterExcludedPaths(in paths: [String]...) -> [String] {
        return paths.flatMap { $0 }
            .filter { path in
                return !excludeByCategorizedGlobs.matches(path: path)
            }
    }
}
