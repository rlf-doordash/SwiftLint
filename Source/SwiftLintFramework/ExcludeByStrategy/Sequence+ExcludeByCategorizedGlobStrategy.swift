//
//  Sequence+ExcludeByCategorizedGlobStrategy.swift
//

extension Sequence where Element == ExcludeByCategorizedGlobStrategy.CategorizedGlobPattern {
    /// Fast path matching using string operations where possible
    func matches(path: String) -> Bool {
        self.contains { pattern in
            pattern.matches(path: path)
        }
    }
}
