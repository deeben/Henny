//
//  AppProfiles.swift
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
import os.log

/// The compatibility profiles Henny uses: the copy built into the app, or a newer one
/// downloaded from next to the Wine runtime. Nothing is sent but a plain request for the file.
public final class AppProfiles: @unchecked Sendable {
    public static let shared = AppProfiles()

    /// Published copy, uploaded to the R2 bucket next to the runtime
    public static let remoteURL = HennyWineInstaller.runtimeBaseURL.appending(path: "profiles.json")

    /// Outside the application support folder, which a runtime install wipes
    static let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: Bundle.hennyBundleIdentifier)
        .appending(path: "profiles.json")

    private let lock = NSLock()
    private var current: AppProfileCatalog

    init() {
        let bundled = Self.load(from: Self.bundledURL)
        let cached = Self.load(from: Self.cacheURL)
        current = [bundled, cached].compactMap { $0 }.max { $0.revision < $1.revision } ?? AppProfileCatalog()
    }

    public var catalog: AppProfileCatalog {
        lock.withLock { current }
    }

    /// The profile for a program, for the installed runtime
    public func profile(forProgramNamed name: String) -> AppProfile? {
        catalog.profile(forProgramNamed: name, runtime: HennyWineInstaller.hennyWineVersion())
    }

    /// Fetch the published file and keep it if it is newer than the one in use.
    /// Failures are silent: the copy in use keeps working offline.
    public func refresh() async {
        var request = URLRequest(url: Self.remoteURL, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let remote = try AppProfileCatalog.decode(data)
            let isNewer = lock.withLock {
                guard remote.revision > current.revision else { return false }
                current = remote
                return true
            }
            guard isNewer else { return }
            try FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: Self.cacheURL, options: .atomic)
            Logger.wineKit.info("Compatibility profiles updated to revision \(remote.revision)")
        } catch {
            Logger.wineKit.info("Compatibility profiles not updated: \(error.localizedDescription)")
        }
    }

    /// `profiles.json` in HennyKit's resource bundle. Looked up by hand because SwiftPM's
    /// `Bundle.module` stops the process when the bundle is missing (e.g. for HennyCmd).
    private static var bundledURL: URL? {
        let bundleName = "HennyKit_HennyKit.bundle"
        let folders = [Bundle.main.resourceURL, Bundle.main.bundleURL,
                       Bundle(for: AppProfiles.self).resourceURL,
                       Bundle.main.executableURL?.deletingLastPathComponent()]
        for folder in folders.compactMap({ $0 }) {
            if let bundle = Bundle(url: folder.appending(path: bundleName)),
               let url = bundle.url(forResource: "profiles", withExtension: "json") {
                return url
            }
        }
        return nil
    }

    private static func load(from url: URL?) -> AppProfileCatalog? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try AppProfileCatalog.decode(data)
        } catch {
            Logger.wineKit.error("Ignoring profiles at \(url.path(percentEncoded: false)): \(error)")
            return nil
        }
    }
}
