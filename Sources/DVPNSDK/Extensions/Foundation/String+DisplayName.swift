//
//  String+DisplayName.swift
//  DVPNSDK
//

import Foundation

extension String {
    /// The longest node or city name the SDK keeps, in characters.
    static let displayNameLimit = 100

    /// A name a node's operator wrote, as an app can show it: without format characters, such as the bidi controls
    /// that reorder the text shown after it, or control characters, and at most `displayNameLimit` characters of at
    /// most `displayNameLimit` × 4 Unicode scalars in all, so combining marks stacked on one character are cut too.
    var displayName: String {
        let kept = String(unicodeScalars.filter { ![.format, .control].contains($0.properties.generalCategory) })
        var name = ""
        var characters = 0
        var scalars = 0
        for character in kept {
            characters += 1
            scalars += character.unicodeScalars.count
            guard characters <= Self.displayNameLimit, scalars <= Self.displayNameLimit * 4 else { break }
            name.append(character)
        }
        return name
    }
}
