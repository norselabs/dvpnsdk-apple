//
//  String+Escaping.swift
//  DVPNSDK
//

import Foundation

package extension String {
    /// This text on one line: line breaks, other control characters and the line and paragraph separators written as
    /// escapes (`\n`, `\r`, `\t`, `\u{1B}`). An engine's text can quote a value a node sent, and a line break in it would
    /// start a line of its own in a log.
    var escapingControlCharacters: String {
        var result = ""
        for scalar in unicodeScalars {
            switch scalar {
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                switch scalar.properties.generalCategory {
                case .control, .lineSeparator, .paragraphSeparator:
                    result += "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
                default:
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }
}
