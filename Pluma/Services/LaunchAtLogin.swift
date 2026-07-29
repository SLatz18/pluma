import ServiceManagement

// pluma's whole job is being resident in the menu bar, so starting at
// login is the default expectation; SMAppService keeps it one call deep.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
