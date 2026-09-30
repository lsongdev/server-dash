//
//  Agent+Notify.swift
//  ServerDash
//

import Foundation
import PTFoundation

extension Agent {
    func prepareNotifications() {
        let token = NotificationCenter.default.addObserver(
            forName: .serverRegistrationChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.updateServerRegistrationInfo()
        }
        notificationObservers.append(token)

        DispatchQueue.global().async {
            self.updateServerRegistrationInfo()
        }
    }

    private func updateServerRegistrationInfo() {
        serverDescriptorsSender = PTServerManager.shared.obtainServerList().map(\.uuid)
        serverSectionsSender = PTServerManager.shared.obtainRegisteredServerSectionList()
    }
}
