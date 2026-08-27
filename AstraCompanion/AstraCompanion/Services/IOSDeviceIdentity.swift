//
//  IOSDeviceIdentity.swift
//  AstraCompanion
//
//  Created by Alex on 23/8/26.
//

import Foundation
import UIKit

enum IOSDeviceIdentity {
    private static let key = "astra.ios.device.id"

    static var current: String {
        if let existing = UserDefaults.standard.string(forKey: key),
           !existing.isEmpty {
            return existing
        }

        let vendor = UIDevice.current.identifierForVendor?.uuidString
        let newValue = vendor?.isEmpty == false ? vendor! : UUID().uuidString

        UserDefaults.standard.set(newValue, forKey: key)
        return newValue
    }

    static var sourceDeviceName: String {
        "ios-\(current)"
    }
}
