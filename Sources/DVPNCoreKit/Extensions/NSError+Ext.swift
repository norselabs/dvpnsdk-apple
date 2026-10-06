//
//  NSError+Ext.swift
//  DVPNCore
//

import Foundation

package extension NSError {
    static func newError(_ message: String) -> NSError {
        NSError(domain: "io.dvpn.tunnel", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
