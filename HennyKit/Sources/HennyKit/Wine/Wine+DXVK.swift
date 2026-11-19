//
//  Wine+DXVK.swift
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

extension Wine {
    /// Wine's own builtin DLLs in the runtime, which include D3DMetal's dxgi and d3d11
    private static let runtimeDLLFolder: URL = HennyWineInstaller.libraryFolder
        .appending(path: "Wine/lib/wine")

    /// Puts DXVK's DLLs in the bottle when DXVK is on, and Wine's (D3DMetal's) back when it is off.
    /// Without the second half, turning DXVK off leaves DXVK in place and D3DMetal never loads.
    static func syncDXVK(bottle: Bottle) throws {
        if bottle.settings.dxvk {
            try enableDXVK(bottle: bottle)
        } else {
            try disableDXVK(bottle: bottle)
        }
    }

    public static func enableDXVK(bottle: Bottle) throws {
        for folders in dllFolders(for: bottle) {
            try FileManager.default.replaceDLLs(in: folders.system, withContentsIn: folders.dxvk)
        }
    }

    public static func disableDXVK(bottle: Bottle) throws {
        let fileManager = FileManager.default
        for folders in dllFolders(for: bottle) {
            let system = folders.system, dxvk = folders.dxvk, runtime = folders.runtime
            let names = (try? fileManager.contentsOfDirectory(atPath: dxvk.path(percentEncoded: false))) ?? []
            for name in names where name.hasSuffix(".dll") {
                let installed = system.appending(path: name)
                let original = runtime.appending(path: name)
                // Only touch files that are still DXVK's, so anything else the user changed stays.
                guard fileManager.contentsEqual(
                    atPath: installed.path(percentEncoded: false),
                    andPath: dxvk.appending(path: name).path(percentEncoded: false)
                ), fileManager.fileExists(atPath: original.path(percentEncoded: false)) else { continue }
                try fileManager.replaceFile(at: installed, with: original, makeOriginalCopy: false)
            }
        }
    }

    private struct DLLFolders {
        let system: URL, dxvk: URL, runtime: URL
    }

    /// The bottle's system folder, DXVK's folder and the runtime's folder, for 64-bit and 32-bit DLLs
    private static func dllFolders(for bottle: Bottle) -> [DLLFolders] {
        let windows = bottle.url.appending(path: "drive_c").appending(path: "windows")
        return [
            DLLFolders(system: windows.appending(path: "system32"), dxvk: dxvkFolder.appending(path: "x64"),
                       runtime: runtimeDLLFolder.appending(path: "x86_64-windows")),
            DLLFolders(system: windows.appending(path: "syswow64"), dxvk: dxvkFolder.appending(path: "x32"),
                       runtime: runtimeDLLFolder.appending(path: "i386-windows"))
        ]
    }
}
