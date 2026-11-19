//
//  PrivilegedCommandReason.swift
//  PHP Monitor
//
//  Created by Nico Verbruggen on 27/04/2026.
//  Copyright © 2026 Nico Verbruggen. All rights reserved.
//

enum PrivilegedCommandReason {
    case onboardingValetTemporarySudoersInstall
    case onboardingValetTemporarySudoersCleanup
    case restoreHomebrewOwnership
    // TODO: add other commands that use AppleScript, so that they can use this abstraction, too!

    var localizedDescription: String {
        switch self {
        case .onboardingValetTemporarySudoersInstall:
            return "privileged_command.reason.onboarding_valet_temporary_sudoers_install".localized
        case .onboardingValetTemporarySudoersCleanup:
            return "privileged_command.reason.onboarding_valet_temporary_sudoers_cleanup".localized
        case .restoreHomebrewOwnership:
            return "privileged_command.reason.restore_homebrew_ownership".localized
        }
    }
}
