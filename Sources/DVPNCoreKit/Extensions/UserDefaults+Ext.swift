//
//  UserDefaults+Ext.swift
//  DVPNCore
//

import Foundation

package extension UserDefaults {
    static var shared: UserDefaults { TunnelEnvironment.sharedDefaults }
}
