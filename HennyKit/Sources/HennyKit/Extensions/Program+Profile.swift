//
//  Program+Profile.swift
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
import AppKit
import os.log

/// One bottle change a compatibility profile asks for
enum ProfileStep: Sendable {
    case graphics(dxvk: Bool)
    case windowsVersion(WinVersion)
    case enhancedSync(EnhancedSync)
    case avx(Bool)
    case dpi(Int)
    case retina(Bool)
    case registry(RegistryValue)
    case winetricks([String])

    var isWinetricks: Bool {
        if case .winetricks = self { return true }
        return false
    }

    var summary: String {
        switch self {
        case .graphics(let dxvk):
            return dxvk
                ? String(localized: "profile.step.dxvkOn", defaultValue: "Turn DXVK on")
                : String(localized: "profile.step.dxvkOff", defaultValue: "Turn DXVK off, so D3DMetal is used")
        case .windowsVersion(let version):
            return String(localized: "profile.step.winVersion",
                          defaultValue: "Set the Windows version to \(version.pretty())")
        case .enhancedSync(let sync):
            let name = switch sync {
            case .none: "none"
            case .esync: "ESync"
            case .msync: "MSync"
            }
            return String(localized: "profile.step.sync", defaultValue: "Set enhanced sync to \(name)")
        case .avx(let enabled):
            return enabled
                ? String(localized: "profile.step.avxOn", defaultValue: "Turn AVX on")
                : String(localized: "profile.step.avxOff", defaultValue: "Turn AVX off")
        case .dpi(let dpi):
            return String(localized: "profile.step.dpi", defaultValue: "Set the bottle's DPI to \(dpi)")
        case .retina(let enabled):
            return enabled
                ? String(localized: "profile.step.retinaOn", defaultValue: "Turn Retina mode on")
                : String(localized: "profile.step.retinaOff", defaultValue: "Turn Retina mode off")
        case .registry(let value):
            return String(localized: "profile.step.registry",
                          defaultValue: "Set \(value.key)\\\(value.name) to \"\(value.data)\"")
        case .winetricks(let verbs):
            return String(localized: "profile.step.winetricks",
                          defaultValue: "Install with Winetricks: \(verbs.joined(separator: ", "))")
        }
    }
}

extension EnhancedSync {
    init?(profileValue: String) {
        switch profileValue.lowercased() {
        case "none": self = .none
        case "esync": self = .esync
        case "msync": self = .msync
        default: return nil
        }
    }
}

extension Program {
    /// Offers the profile's one-time bottle setup the first time the program is opened,
    /// and again only if the profile's setup changes. Returns whether to launch now.
    func prepareProfileSetup() async -> Bool {
        guard let profile, profile.hasSetup else { return true }
        let key = profile.setupKey
        guard settings.profileSetup != key else { return true }

        let steps = await pendingSteps(for: profile)
        guard !steps.isEmpty || profile.notice != nil else {
            await MainActor.run { self.settings.profileSetup = key }
            return true
        }

        let choice = await MainActor.run { self.askAboutSetup(profile: profile, steps: steps) }
        guard choice != .cancel else { return false }
        await MainActor.run { self.settings.profileSetup = key }
        guard choice == .apply else { return true }

        for step in steps {
            do {
                try await apply(step)
            } catch {
                Logger.wineKit.error("Profile `\(profile.id)` step failed: \(step.summary): \(error)")
            }
        }
        // Winetricks runs in Terminal; the program should start only once it has finished
        return !steps.contains(where: \.isWinetricks)
    }

    /// The profile's changes this bottle doesn't have yet
    func pendingSteps(for profile: AppProfile) async -> [ProfileStep] {
        var steps: [ProfileStep] = []
        if let wanted = profile.bottle {
            steps += settingsSteps(for: wanted)
            if let dpi = wanted.dpi, (try? await Wine.dpiResolution(bottle: bottle)) != dpi {
                steps.append(.dpi(dpi))
            }
            if let retina = wanted.retina, (try? await Wine.retinaMode(bottle: bottle)) != retina {
                steps.append(.retina(retina))
            }
        }
        steps += profile.registry.map { .registry($0) }
        if !profile.winetricks.isEmpty {
            steps.append(.winetricks(profile.winetricks))
        }
        return steps
    }

    /// Differences from the bottle's own settings, which need no Wine call to check
    private func settingsSteps(for wanted: BottleRequirements) -> [ProfileStep] {
        var steps: [ProfileStep] = []
        let current = bottle.settings
        switch wanted.graphics?.lowercased() ?? "" {
        case "d3dmetal" where current.dxvk: steps.append(.graphics(dxvk: false))
        case "dxvk" where !current.dxvk: steps.append(.graphics(dxvk: true))
        default: break
        }
        if let version = wanted.windowsVersion.flatMap(WinVersion.init(rawValue:)),
           version != current.windowsVersion {
            steps.append(.windowsVersion(version))
        }
        if let sync = wanted.enhancedSync.flatMap(EnhancedSync.init(profileValue:)), sync != current.enhancedSync {
            steps.append(.enhancedSync(sync))
        }
        if let avx = wanted.avx, avx != current.avxEnabled {
            steps.append(.avx(avx))
        }
        return steps
    }

    private func apply(_ step: ProfileStep) async throws {
        switch step {
        case .graphics(let dxvk):
            // Wine.runProgram puts the matching DLLs in place on launch
            await MainActor.run { bottle.settings.dxvk = dxvk }
        case .windowsVersion(let version):
            try await Wine.changeWinVersion(bottle: bottle, win: version)
            await MainActor.run { bottle.settings.windowsVersion = version }
        case .enhancedSync(let sync):
            await MainActor.run { bottle.settings.enhancedSync = sync }
        case .avx(let enabled):
            await MainActor.run { bottle.settings.avxEnabled = enabled }
        case .dpi(let dpi):
            try await Wine.changeDpiResolution(bottle: bottle, dpi: dpi)
        case .retina(let enabled):
            try await Wine.changeRetinaMode(bottle: bottle, retinaMode: enabled)
        case .registry(let value):
            try await Wine.runWine(
                ["reg", "add", value.key, "-v", value.name, "-t", value.type, "-d", value.data, "-f"],
                bottle: bottle
            )
        case .winetricks(let verbs):
            await MainActor.run { WinetricksRunner.openInTerminal(arguments: ["-q"] + verbs, bottle: bottle) }
        }
    }

    enum SetupChoice: Sendable {
        case apply, skip, cancel
    }

    @MainActor private func askAboutSetup(profile: AppProfile, steps: [ProfileStep]) -> SetupChoice {
        let alert = NSAlert()
        alert.alertStyle = .informational
        var lines: [String] = []
        if !steps.isEmpty {
            alert.messageText = String(localized: "profile.setup.title", defaultValue: "Set up \(profile.name)?")
            lines.append(String(
                localized: "profile.setup.intro",
                defaultValue: "Henny knows settings that help \(name) run. This changes the whole bottle:"
            ))
            lines += steps.map { "• " + $0.summary }
        } else {
            alert.messageText = profile.name
        }
        if let notice = profile.notice {
            lines.append(notice)
        }
        if steps.contains(where: \.isWinetricks) {
            lines.append(String(localized: "profile.setup.winetricks",
                                defaultValue: "Winetricks opens in Terminal. Open \(name) again when it has finished."))
        }
        alert.informativeText = lines.joined(separator: "\n\n")

        if steps.isEmpty {
            alert.addButton(withTitle: String(localized: "profile.setup.open", defaultValue: "Open"))
            alert.addButton(withTitle: String(localized: "button.removeAlert.cancel"))
            return alert.runModal() == .alertFirstButtonReturn ? .skip : .cancel
        }
        alert.addButton(withTitle: String(localized: "profile.setup.apply", defaultValue: "Apply and Open"))
        alert.addButton(withTitle: String(localized: "profile.setup.skip", defaultValue: "Open Without Changes"))
        alert.addButton(withTitle: String(localized: "button.removeAlert.cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .apply
        case .alertSecondButtonReturn: return .skip
        default: return .cancel
        }
    }
}

/// Runs winetricks for a bottle in Terminal, so the user can see what it does
public enum WinetricksRunner {
    public static let winetricksURL: URL = HennyWineInstaller.libraryFolder.appending(path: "winetricks")

    /// The shell command, escaped for an AppleScript string
    public static func terminalCommand(arguments: String, bottle: Bottle) -> String? {
        guard let resourcesURL = Bundle.main.url(forResource: "cabextract", withExtension: nil)?
            .deletingLastPathComponent() else { return nil }
        let path = "\(HennyWineInstaller.binFolder.path):\(resourcesURL.path(percentEncoded: false)):$PATH"
        let winetricks = winetricksURL.path(percentEncoded: false)
        return #"PATH=\"\#(path)\" WINE=wine64 WINEPREFIX=\"\#(bottle.url.path)\" \"\#(winetricks)\" \#(arguments)"#
    }

    @MainActor public static func openInTerminal(arguments: [String], bottle: Bottle) {
        guard let command = terminalCommand(arguments: arguments.joined(separator: " "), bottle: bottle) else {
            return
        }
        let script = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            Logger.wineKit.error("Failed to start winetricks: \(error)")
        }
    }
}
