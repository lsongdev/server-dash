//
//  PTServerManager+Notifications.swift
//  PTFoundation
//

import Foundation

public extension Notification.Name {
    static let serverRegistrationChanged = Notification.Name(
        "org.lsong.serverdash.server.registration.changed"
    )

    static let serverStatusUpdated = Notification.Name(
        "org.lsong.serverdash.server.status.updated"
    )
}
