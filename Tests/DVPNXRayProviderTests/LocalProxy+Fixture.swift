//
//  LocalProxy+Fixture.swift
//  DVPNCore
//

import DVPNCoreKit

extension LocalProxy {
    /// Fixed values for documents that tests compare; the extension makes random ones for every start.
    static let fixture = LocalProxy(port: 8080, username: "user", password: "pass")
}
