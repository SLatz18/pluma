import Foundation

/// Loads style profiles from three sources (issue #20):
/// built-ins, custom JSON files, and MDM-managed profiles.
enum StyleProfileStore {
    /// UserDefaults key for MDM-pushed profiles (JSON array of StyleProfile).
    /// Managed profiles replace custom ones and are read-only in the UI.
    static let managedProfilesKey = "rewrite.managedStyleProfiles"

    static func availableProfiles(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> [StyleProfile] {
        var profiles = StyleProfile.builtIns

        if let managed = managedProfiles(defaults: defaults), !managed.isEmpty {
            // Managed profiles are authoritative: built-in "none" stays
            // available, the rest of the list is the organization's.
            return [.none] + managed
        }

        profiles += customProfiles(fileManager: fileManager)
        return profiles
    }

    static func profile(
        id: String,
        defaults: UserDefaults = .standard
    ) -> StyleProfile {
        availableProfiles(defaults: defaults).first { $0.id == id } ?? .none
    }

    /// MDM: admins push a JSON array of profile objects via managed
    /// preferences. Malformed payloads fail closed (built-ins only).
    static func managedProfiles(defaults: UserDefaults) -> [StyleProfile]? {
        guard let raw = defaults.string(forKey: managedProfilesKey),
              let data = raw.data(using: .utf8),
              var decoded = try? JSONDecoder().decode([StyleProfile].self, from: data)
        else { return nil }
        for index in decoded.indices { decoded[index].isManaged = true }
        return decoded
    }

    /// Custom profiles: *.json files in
    /// ~/Library/Application Support/Rewrite/StyleProfiles/.
    /// Intentionally no in-app editor yet — JSON-first keeps profiles
    /// reviewable in git/diff form before a UI commits to a schema.
    static func customProfiles(fileManager: FileManager = .default) -> [StyleProfile] {
        guard
            let support = fileManager.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else { return [] }

        let directory = support
            .appending(path: "Rewrite", directoryHint: .isDirectory)
            .appending(path: "StyleProfiles", directoryHint: .isDirectory)

        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard
                    let data = try? Data(contentsOf: url),
                    let profile = try? decoder.decode(StyleProfile.self, from: data)
                else { return nil }
                return profile
            }
    }
}
