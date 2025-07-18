//
//  PartialSubPathExcluder.swift
//

/// A protocol that indicates we can partially check for paths and exclude them completely without traversing

public protocol PartialSubPathExcluder {
    func isExcluded(path: String) -> Bool
}
