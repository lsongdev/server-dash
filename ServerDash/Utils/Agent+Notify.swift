//
//  Agent+Notify.swift
//  ServerDash
//

import PTFoundation
import UIKit

extension Agent {
    func prepareNotifications() {
        let serverCountLink = PTNotificationCenter.NotificationLink(
            name: .ServerManager_RegistrationChanged,
            throttle: PTThrottle(minimumDelay: 1, queue: .global())
        ) { _ in
            self.updateServerRegistrationInfo()
        }
        PTNotificationCenter.shared.registeringNotification(withLink: serverCountLink)

        DispatchQueue.global().async {
            self.updateServerRegistrationInfo()
        }
    }

    private func updateServerRegistrationInfo() {
        serverDescriptorsSender = PTServerManager.shared.obtainServerList().map(\.uuid)
        serverSectionsSender = PTServerManager.shared.obtainRegisteredServerSectionList()
    }
}
