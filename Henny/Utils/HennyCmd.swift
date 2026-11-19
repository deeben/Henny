//
//  HennyCmd.swift
//  Henny
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

class HennyCmd {
    static func install() async {
        let hennyCmdURL = Bundle.main.url(forResource: "HennyCmd", withExtension: nil)

        if let hennyCmdURL = hennyCmdURL {
            // swiftlint:disable line_length
            let script = """
            do shell script "ln -fs \(hennyCmdURL.path(percentEncoded: false)) /usr/local/bin/henny" with administrator privileges
            """
            // swiftlint:enable line_length

            var error: NSDictionary?
            // Use AppleScript because somehow in 2023 Apple doesn't have good privileged file ops APIs
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)

                if let error = error {
                    print(error)
                    if let description = error["NSAppleScriptErrorMessage"] as? String {
                        await MainActor.run {
                            let alert = NSAlert()
                            alert.messageText = String(localized: "alert.message")
                            alert.informativeText = String(localized: "alert.info")
                                + description
                            alert.alertStyle = .critical
                            alert.addButton(withTitle: String(localized: "button.ok"))
                            alert.runModal()
                        }
                    }
                }
            }
        }
    }
}
