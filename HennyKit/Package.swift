// swift-tools-version: 5.9
//
//  Package.swift
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

import PackageDescription

let package = Package(
    name: "HennyKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "HennyKit",
            targets: ["HennyKit"]
        )
    ],
    dependencies: [
        // HennyKit only needs SemanticVersion. The command-line tool's packages
        // (ArgumentParser, SwiftyTextTable, Progress) are linked to the HennyCmd
        // target in the Xcode project, not here. Use the same https URL as the
        // Xcode project so both resolve to one copy without needing SSH keys.
        .package(url: "https://github.com/SwiftPackageIndex/SemanticVersion", from: "0.3.6")
    ],
    targets: [
        .target(
            name: "HennyKit",
            dependencies: ["SemanticVersion"]
        )
    ],
    swiftLanguageVersions: [.version("6")]
)
