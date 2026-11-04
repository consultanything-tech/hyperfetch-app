//
//  LaunchAtLoginController.swift
//  DownloadKit
//

import Foundation
import ServiceManagement

/// Representation of the system Launch at Login registration status.
public enum LaunchAtLoginStatus: String, Sendable, Equatable, CaseIterable {
    case enabled = "Enabled"
    case notRegistered = "Not Registered"
    case requiresApproval = "Requires Approval"
    case notFound = "Not Found"
}

/// Abstraction layer over ServiceManagement to facilitate unit testing.
public protocol LaunchAtLoginServiceProtocol: Sendable {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

/// Concrete implementation wrapping Apple's macOS 13+ ServiceManagement SMAppService.
public final class SMAppServiceWrapper: LaunchAtLoginServiceProtocol, @unchecked Sendable {
    public init() {}

    public var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .notRegistered
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    public func register() throws {
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Controller managing launch at login persistence and system synchronization.
public final class LaunchAtLoginController: @unchecked Sendable {
    public static let userDefaultsKey = "com.hyperfetch.launchAtLogin"

    private let service: LaunchAtLoginServiceProtocol
    private let userDefaults: UserDefaults

    public init(
        service: LaunchAtLoginServiceProtocol = SMAppServiceWrapper(),
        userDefaults: UserDefaults = .standard
    ) {
        self.service = service
        self.userDefaults = userDefaults
    }

    public var status: LaunchAtLoginStatus {
        service.status
    }

    public var isEnabledInPreferences: Bool {
        userDefaults.bool(forKey: Self.userDefaultsKey)
    }

    public func sync(defaultIfUnset: Bool = true) {
        if userDefaults.object(forKey: Self.userDefaultsKey) == nil {
            if defaultIfUnset {
                userDefaults.set(true, forKey: Self.userDefaultsKey)
                try? service.register()
            } else {
                userDefaults.set(false, forKey: Self.userDefaultsKey)
            }
        } else {
            if isEnabledInPreferences {
                try? service.register()
            } else {
                try? service.unregister()
            }
        }
    }

    @discardableResult
    public func setLaunchAtLogin(enabled: Bool) -> LaunchAtLoginStatus {
        userDefaults.set(enabled, forKey: Self.userDefaultsKey)
        if enabled {
            try? service.register()
        } else {
            try? service.unregister()
        }
        return service.status
    }

    public func openSystemSettings() {
        service.openSystemSettings()
    }
}
