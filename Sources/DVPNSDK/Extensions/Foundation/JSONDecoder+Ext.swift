//
//  JSONDecoder+Ext.swift
//  DVPNSDK
//

import Foundation

extension JSONDecoder {
    /// Decoder for the node metadata inside credentials (`ConnectionCredentials`), whose models have no
    /// `CodingKeys`. Backend response models spell their keys out and use a plain `JSONDecoder()`.
    static var snakeCase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
