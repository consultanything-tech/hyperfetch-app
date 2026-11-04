//
//  LaunchAtLoginTests.swift
//  DownloadKitTests
//
//  Created by HyperFetch on 2026-11-04.
//

import Testing
import Foundation
@testable import DownloadKit

final class MockLaunchAtLoginService: LaunchAtLoginServiceProtocol, @unchecked Sendable {
    var status: LaunchAtLoginStatus = .notRegistered
    var registerCallCount = 0
    var unregisterCallCount = 0
    var openSystemSettingsCallCount = 0
    var shouldThrowOnRegister = false
    var shouldThrowOnUnregister = false
    var errorToThrow: (any Error)?

    func register() throws {
        registerCallCount += 1
        if shouldThrowOnRegister {
            throw errorToThrow ?? NSError(
                domain: "SMAppServiceErrorDomain",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Registration failed"]
            )
        }
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if shouldThrowOnUnregister {
            throw errorToThrow ?? NSError(
                domain: "SMAppServiceErrorDomain",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unregistration failed"]
            )
        }
        status = .notRegistered
    }

    func openSystemSettings() {
        openSystemSettingsCallCount += 1
    }
}

@Suite("Launch at Login & Autostart Tests")
struct LaunchAtLoginTests {

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "com.hyperfetch.tests.launchatlogin.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, suiteName)
    }

    @Test("Status enum raw values match expected display labels")
    func testStatusEnumRawValues() {
        #expect(LaunchAtLoginStatus.enabled.rawValue == "Enabled")
        #expect(LaunchAtLoginStatus.notRegistered.rawValue == "Not Registered")
        #expect(LaunchAtLoginStatus.requiresApproval.rawValue == "Requires Approval")
        #expect(LaunchAtLoginStatus.notFound.rawValue == "Not Found")
    }

    @Test("First run default enablement registers service and updates UserDefaults")
    func testFirstRunDefaultEnablement() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let mockService = MockLaunchAtLoginService()
        let controller = LaunchAtLoginController(service: mockService, userDefaults: defaults)

        #expect(defaults.object(forKey: LaunchAtLoginController.userDefaultsKey) == nil)

        controller.sync(defaultIfUnset: true)

        #expect(defaults.bool(forKey: LaunchAtLoginController.userDefaultsKey) == true)
        #expect(controller.isEnabledInPreferences == true)
        #expect(mockService.registerCallCount == 1)
        #expect(mockService.unregisterCallCount == 0)
        #expect(controller.status == .enabled)
    }

    @Test("First run with defaultIfUnset false does not register service")
    func testFirstRunWithDefaultIfUnsetFalse() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let mockService = MockLaunchAtLoginService()
        let controller = LaunchAtLoginController(service: mockService, userDefaults: defaults)

        controller.sync(defaultIfUnset: false)

        #expect(defaults.bool(forKey: LaunchAtLoginController.userDefaultsKey) == false)
        #expect(controller.isEnabledInPreferences == false)
        #expect(mockService.registerCallCount == 0)
        #expect(mockService.unregisterCallCount == 0)
        #expect(controller.status == .notRegistered)
    }

    @Test("Sync respects pre-existing enabled preference")
    func testSyncRespectsPreExistingEnabledPreference() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: LaunchAtLoginController.userDefaultsKey)

        let mockService = MockLaunchAtLoginService()
        let controller = LaunchAtLoginController(service: mockService, userDefaults: defaults)

        controller.sync()

        #expect(mockService.registerCallCount == 1)
        #expect(mockService.unregisterCallCount == 0)
        #expect(controller.isEnabledInPreferences == true)
    }

    @Test("Sync respects pre-existing disabled preference")
    func testSyncRespectsPreExistingDisabledPreference() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(false, forKey: LaunchAtLoginController.userDefaultsKey)

        let mockService = MockLaunchAtLoginService()
        mockService.status = .enabled
        let controller = LaunchAtLoginController(service: mockService, userDefaults: defaults)

        controller.sync()

        #expect(mockService.registerCallCount == 0)
        #expect(mockService.unregisterCallCount == 1)
        #expect(controller.isEnabledInPreferences == false)
        #expect(controller.status == .notRegistered)
    }

    @Test("Disabling launch at login unregisters service and updates UserDefaults")
    func testDisablingLaunchAtLogin() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let mockService = MockLaunchAtLoginService()
        let controller = LaunchAtLoginController(service: mockService, userDefaults: defaults)

        controller.sync(defaultIfUnset: true)
        #expect(controller.isEnabledInPreferences == true)

        let statusAfterDisable = controller.setLaunchAtLogin(enabled: false)

        #expect(defaults.bool(forKey: LaunchAtLoginController.userDefaultsKey) == false)
        #expect(controller.isEnabledInPreferences == false)
        #expect(mockService.unregisterCallCount == 1)
        #expect(statusAfterDisable == .notRegistered)
        #expect(controller.status == .notRegistered)
    }

    @Test("Re-enabling launch at login registers service and updates UserDefaults")
    func testReEnablingLaunchAtLogin() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let mockService = MockLaunchAtLoginService()
        let controller = LaunchAtLoginController(service: mockService, userDefaults: defaults)

        controller.setLaunchAtLogin(enabled: false)
        #expect(mockService.unregisterCallCount == 1)
        #expect(controller.isEnabledInPreferences == false)

        let statusAfterEnable = controller.setLaunchAtLogin(enabled: true)

        #expect(defaults.bool(forKey: LaunchAtLoginController.userDefaultsKey) == true)
        #expect(controller.isEnabledInPreferences == true)
        #expect(mockService.registerCallCount == 1)
        #expect(statusAfterEnable == .enabled)
        #expect(controller.status == .enabled)
    }

    @Test("Requires approval status is reflected and openSystemSettings forwards")
    func testRequiresApprovalAndSystemSettings() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let mockService = MockLaunchAtLoginService()
        mockService.status = .requiresApproval
        let controller = LaunchAtLoginController(service: mockService, userDefaults: defaults)

        #expect(controller.status == .requiresApproval)

        controller.openSystemSettings()
        #expect(mockService.openSystemSettingsCallCount == 1)
    }

    @Test("Graceful behavior when service registration or unregistration throws")
    func testErrorHandlingWhenServiceThrows() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let mockService = MockLaunchAtLoginService()
        mockService.shouldThrowOnRegister = true
        let controller = LaunchAtLoginController(service: mockService, userDefaults: defaults)

        // Should not throw or crash
        let statusOnFail = controller.setLaunchAtLogin(enabled: true)
        #expect(defaults.bool(forKey: LaunchAtLoginController.userDefaultsKey) == true)
        #expect(mockService.registerCallCount == 1)
        #expect(statusOnFail == .notRegistered)

        mockService.shouldThrowOnUnregister = true
        // Should not throw or crash
        controller.setLaunchAtLogin(enabled: false)
        #expect(defaults.bool(forKey: LaunchAtLoginController.userDefaultsKey) == false)
        #expect(mockService.unregisterCallCount == 1)
    }
}
