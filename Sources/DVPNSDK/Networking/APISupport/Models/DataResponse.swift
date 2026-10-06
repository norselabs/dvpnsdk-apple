//
//  DataResponse.swift
//  DVPNSDK
//

import Foundation

public struct DataResponse<T: Decodable & Sendable>: Decodable, Sendable {
    public let data: T
}
