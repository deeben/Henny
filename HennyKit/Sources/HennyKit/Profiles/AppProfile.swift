//
//  AppProfile.swift
//  HennyKit
//
//  This file is part of Henny.
//
//  Henny is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Henny is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Henny.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation
import SemanticVersion

/// The compatibility profiles file (`profiles.json`): known-good settings for programs,
/// matched by file name. See `Profiles.md` at the repository root for the format.
public struct AppProfileCatalog: Codable, Sendable, Equatable {
    /// The newest file format this version of Henny understands
    public static let supportedFormat = 1

    /// Bumped when a change to the file would break older copies of Henny
    public var format: Int
    /// Bumped on every published change. Henny keeps whichever copy has the highest revision.
    public var revision: Int
    public var updated: String?
    public var profiles: [AppProfile]

    public init(format: Int = supportedFormat, revision: Int = 0, updated: String? = nil,
                profiles: [AppProfile] = []) {
        self.format = format
        self.revision = revision
        self.updated = updated
        self.profiles = profiles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.format = try container.decode(Int.self, forKey: .format)
        self.revision = try container.decode(Int.self, forKey: .revision)
        self.updated = try container.decodeIfPresent(String.self, forKey: .updated)
        // One bad entry (a typo, or a field from a newer Henny) must not throw away the rest
        let entries = try container.decodeIfPresent([LossyProfile].self, forKey: .profiles) ?? []
        self.profiles = entries.compactMap(\.profile)
    }

    public static func decode(_ data: Data) throws -> AppProfileCatalog {
        let catalog = try JSONDecoder().decode(AppProfileCatalog.self, from: data)
        guard catalog.format <= supportedFormat else {
            throw AppProfileError.unsupportedFormat(catalog.format)
        }
        return catalog
    }

    /// The first profile listing this program whose runtime range includes `runtime`
    public func profile(forProgramNamed name: String, runtime: SemanticVersion?) -> AppProfile? {
        let name = name.lowercased()
        return profiles.first { profile in
            profile.programs.contains { $0.lowercased() == name } && profile.supports(runtime: runtime)
        }
    }

    private struct LossyProfile: Decodable {
        let profile: AppProfile?

        init(from decoder: Decoder) throws {
            profile = try? AppProfile(from: decoder)
        }
    }
}

public enum AppProfileError: Error {
    case unsupportedFormat(Int)
}

public struct AppProfile: Codable, Sendable, Equatable {
    /// Stable identifier, e.g. `battlenet`. Henny remembers per program which profile setup it offered.
    public var id: String
    public var name: String
    /// Executable file names this profile applies to, compared without regard to case
    public var programs: [String]
    /// Lowest runtime version (`HennyWineVersion.plist`) this entry is for
    public var minRuntime: String?
    /// The entry is for runtimes older than this version
    public var runtimeBelow: String?

    // Applied on every launch. The user's own arguments and variables win.
    public var arguments: [String]
    public var environment: [String: String]
    /// DLL name to Wine load order, e.g. `"d3d11": "n,b"` or `"overlay.dll": "d"`
    public var dllOverrides: [String: String]

    // One-time setup Henny shows the user and asks about before applying.
    public var bottle: BottleRequirements?
    public var registry: [RegistryValue]
    public var winetricks: [String]
    /// Shown to the user when the program is first opened, e.g. a known problem
    public var notice: String?

    /// For people reading the file: why these settings are needed
    public var notes: String?
    public var tested: TestReport?

    public init(id: String, name: String, programs: [String]) {
        self.id = id
        self.name = name
        self.programs = programs
        self.arguments = []
        self.environment = [:]
        self.dllOverrides = [:]
        self.registry = []
        self.winetricks = []
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
        programs = try container.decode([String].self, forKey: .programs)
        minRuntime = try container.decodeIfPresent(String.self, forKey: .minRuntime)
        runtimeBelow = try container.decodeIfPresent(String.self, forKey: .runtimeBelow)
        arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
        environment = try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        dllOverrides = try container.decodeIfPresent([String: String].self, forKey: .dllOverrides) ?? [:]
        bottle = try container.decodeIfPresent(BottleRequirements.self, forKey: .bottle)
        registry = try container.decodeIfPresent([RegistryValue].self, forKey: .registry) ?? []
        winetricks = try container.decodeIfPresent([String].self, forKey: .winetricks) ?? []
        notice = try container.decodeIfPresent(String.self, forKey: .notice)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        tested = try container.decodeIfPresent(TestReport.self, forKey: .tested)
    }

    public func supports(runtime: SemanticVersion?) -> Bool {
        let minimum = minRuntime.flatMap(SemanticVersion.init)
        let below = runtimeBelow.flatMap(SemanticVersion.init)
        guard minimum != nil || below != nil else { return true }
        // Unknown runtime: only entries that don't depend on the version apply
        guard let runtime else { return false }
        if let minimum, runtime < minimum { return false }
        if let below, runtime >= below { return false }
        return true
    }

    /// `WINEDLLOVERRIDES` syntax, sorted so the value is stable
    public var dllOverridesValue: String? {
        guard !dllOverrides.isEmpty else { return nil }
        return dllOverrides.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ";")
    }

    /// Whether the profile has anything to ask the user about
    public var hasSetup: Bool {
        !(bottle?.isEmpty ?? true) || !registry.isEmpty || !winetricks.isEmpty || notice != nil
    }

    /// Identifies this profile's setup, so Henny asks again only when the setup itself changes
    public var setupKey: String {
        struct Setup: Encodable {
            let bottle: BottleRequirements?, registry: [RegistryValue], winetricks: [String], notice: String?
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let setup = Setup(bottle: bottle, registry: registry, winetricks: winetricks, notice: notice)
        let json = (try? encoder.encode(setup)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return "\(id):\(json)"
    }

    /// Adds the profile's arguments that the user hasn't already given
    public func mergedArguments(with userArguments: String) -> String {
        let existing = userArguments.split { $0.isWhitespace }.map(String.init)
        let missing = arguments.filter { !existing.contains($0) }
        return (existing + missing).joined(separator: " ")
    }

    /// The profile's variables and DLL overrides under the user's own
    public func mergedEnvironment(with userEnvironment: [String: String]) -> [String: String] {
        var result = environment
        if let dllOverridesValue {
            result["WINEDLLOVERRIDES"] = dllOverridesValue
        }
        result.merge(userEnvironment) { $1 }
        return result
    }
}

/// Bottle-wide settings a program needs. Every field is optional; missing ones are left alone.
/// Values are kept as strings so a newer file with a new value doesn't break older copies of Henny.
public struct BottleRequirements: Codable, Sendable, Equatable {
    /// `d3dmetal` or `dxvk`. `wined3d` is reserved; Henny doesn't offer it yet and ignores it.
    public var graphics: String?
    /// `win10`, `win11`, ... as in winecfg
    public var windowsVersion: String?
    /// `none`, `esync` or `msync`
    public var enhancedSync: String?
    public var avx: Bool?
    /// Windows DPI (`LogPixels`). Chromium-based programs draw nothing at 0.
    public var dpi: Int?
    /// macOS Retina mode in Wine's Mac driver
    public var retina: Bool?

    public init() {}

    var isEmpty: Bool {
        graphics == nil && windowsVersion == nil && enhancedSync == nil && avx == nil && dpi == nil && retina == nil
    }
}

public struct RegistryValue: Codable, Sendable, Equatable {
    public var key: String
    public var name: String
    /// `REG_SZ`, `REG_DWORD`, `REG_QWORD` or `REG_BINARY`
    public var type: String
    public var data: String
}

public struct TestReport: Codable, Sendable, Equatable {
    public var runtime: String?
    public var date: String?
    /// `works`, `partial` or `broken`
    public var result: String?
    public var with: String?
}
