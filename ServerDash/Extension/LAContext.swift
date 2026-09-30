//
//  LAContext.swift
//  ServerDash
//
//  Created by Lakr Aream on 5/23/21.
//

import Foundation
import LocalAuthentication

extension LAContext {
    enum BiometricType: String {
        case none
        case touchID
        case faceID
        case opticID
    }

    var biometricType: BiometricType {
        var error: NSError?

        guard canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }

        switch self.biometryType {
        case .none:
            return .none
        case .touchID:
            return .touchID
        case .faceID:
            return .faceID
        case .opticID:
            return .opticID
        @unknown default:
            return .none
        }
    }
}
