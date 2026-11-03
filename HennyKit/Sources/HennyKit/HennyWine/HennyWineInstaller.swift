//
//  HennyWineInstaller.swift
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

public class HennyWineInstaller {
    /// Where the Wine runtime and its version plist are hosted.
    /// Change this one value when the runtime moves (e.g. to a Cloudflare R2 bucket).
    /// TEMPORARY: uses Whisky's last published runtime until Henny hosts its own build.
    public static let runtimeBaseURL: URL = {
        guard let url = URL(string: "https://data.getwhisky.app/Wine/") else {
            preconditionFailure("runtimeBaseURL is not a valid URL")
        }
        return url
    }()

    /// The runtime tarball that first-run setup downloads
    public static let runtimeTarballURL = runtimeBaseURL.appending(path: "Libraries.tar.gz")

    /// The Henny application folder
    public static let applicationFolder = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appending(path: Bundle.hennyBundleIdentifier)

    /// The folder of all the libfrary files
    public static let libraryFolder = applicationFolder.appending(path: "Libraries")

    /// URL to the installed `wine` `bin` directory
    public static let binFolder: URL = libraryFolder.appending(path: "Wine").appending(path: "bin")

    public static func isHennyWineInstalled() -> Bool {
        return hennyWineVersion() != nil
    }

    public static func install(from: URL) {
        do {
            if !FileManager.default.fileExists(atPath: applicationFolder.path) {
                try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
            } else {
                // Recreate it
                try FileManager.default.removeItem(at: applicationFolder)
                try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
            }

            try Tar.untar(tarBall: from, toURL: applicationFolder)
            try FileManager.default.removeItem(at: from)

            // Whisky's runtime ships WhiskyWineVersion.plist; accept it under Henny's name.
            let hennyPlist = libraryFolder.appending(path: "HennyWineVersion.plist")
            let whiskyPlist = libraryFolder.appending(path: "WhiskyWineVersion.plist")
            if !FileManager.default.fileExists(atPath: hennyPlist.path(percentEncoded: false)),
               FileManager.default.fileExists(atPath: whiskyPlist.path(percentEncoded: false)) {
                try FileManager.default.copyItem(at: whiskyPlist, to: hennyPlist)
            }
        } catch {
            print("Failed to install HennyWine: \(error)")
        }
    }

    public static func uninstall() {
        do {
            try FileManager.default.removeItem(at: libraryFolder)
        } catch {
            print("Failed to uninstall HennyWine: \(error)")
        }
    }

    public static func shouldUpdateHennyWine() async -> (Bool, SemanticVersion) {
        let localVersion = hennyWineVersion()

        var remoteVersion: SemanticVersion?

        do {
            let remoteUrl = runtimeBaseURL.appending(path: "HennyWineVersion.plist")
            remoteVersion = await withCheckedContinuation { continuation in
                URLSession(configuration: .ephemeral).dataTask(with: URLRequest(url: remoteUrl)) { data, _, error in
                    do {
                        if error == nil, let data = data {
                            let decoder = PropertyListDecoder()
                            let remoteInfo = try decoder.decode(HennyWineVersion.self, from: data)
                            let remoteVersion = remoteInfo.version

                            continuation.resume(returning: remoteVersion)
                            return
                        }
                        if let error = error {
                            print(error)
                        }
                    } catch {
                        print(error)
                    }

                    continuation.resume(returning: nil)
                }.resume()
            }
        }

        if let localVersion = localVersion, let remoteVersion = remoteVersion {
            if localVersion < remoteVersion {
                return (true, remoteVersion)
            }
        }

        return (false, SemanticVersion(0, 0, 0))
    }

    public static func hennyWineVersion() -> SemanticVersion? {
        do {
            let versionPlist = libraryFolder
                .appending(path: "HennyWineVersion")
                .appendingPathExtension("plist")

            let decoder = PropertyListDecoder()
            let data = try Data(contentsOf: versionPlist)
            let info = try decoder.decode(HennyWineVersion.self, from: data)
            return info.version
        } catch {
            print(error)
            return nil
        }
    }
}

struct HennyWineVersion: Codable {
    var version: SemanticVersion = SemanticVersion(11, 7, 0)
}
