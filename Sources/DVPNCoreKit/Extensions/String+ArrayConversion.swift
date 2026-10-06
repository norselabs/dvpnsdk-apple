//
//  String+ArrayConversion.swift
//  DVPNCore
//

import Foundation

package extension String {
    func splitToArray(separator: Character = ",", trimmingCharacters: CharacterSet? = nil) -> [String] {
        split(separator: separator)
            .map {
                guard let charSet = trimmingCharacters else { return String($0) }
                return $0.trimmingCharacters(in: charSet)
            }
    }
}

package extension String? {
    func splitToArray(separator: Character = ",", trimmingCharacters: CharacterSet? = nil) -> [String] {
        self?.splitToArray(separator: separator, trimmingCharacters: trimmingCharacters) ?? []
    }
}
