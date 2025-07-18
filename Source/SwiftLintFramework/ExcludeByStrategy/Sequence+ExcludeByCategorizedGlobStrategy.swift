//
//  Sequence+ExcludeByCategorizedGlobStrategy.swift
//

extension Sequence where Element == ExcludeByCategorizedGlobStrategy.CategorizedGlobPattern {
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
