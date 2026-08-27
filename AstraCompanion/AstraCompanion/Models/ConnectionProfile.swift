//
//  ConnectionProfile.swift
//  AstraCompanion
//
//  Created by Alex on 13/8/26.
//

import Foundation

struct ConnectionProfile: Codable, Equatable {
    var macUID: String
    var macDeviceID: String
    var conversationId: String?
}
