//
//  HennyWineDownloadView.swift
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

import SwiftUI
import HennyKit

struct HennyWineDownloadView: View {
    @State private var fractionProgress: Double = 0
    @State private var completedBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var downloadSpeed: Double = 0
    @State private var downloadTask: URLSessionDownloadTask?
    @State private var observation: NSKeyValueObservation?
    @State private var startTime: Date?
    @State private var errorMessage: String?
    @Binding var tarLocation: URL
    @Binding var path: [SetupStage]
    var body: some View {
        VStack {
            VStack {
                Text("setup.hennywine.download")
                    .font(.title)
                    .fontWeight(.bold)
                Text("setup.hennywine.download.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack {
                    if let errorMessage {
                        Text(verbatim: errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                        Button("button.retry") {
                            startDownload()
                        }
                    } else {
                        ProgressView(value: fractionProgress, total: 1)
                    }
                    HStack {
                        HStack {
                            Text(String(format: String(localized: "setup.hennywine.progress"),
                                        formatBytes(bytes: completedBytes),
                                        formatBytes(bytes: totalBytes)))
                            + Text(String(" "))
                            + (shouldShowEstimate() ?
                               Text(String(format: String(localized: "setup.hennywine.eta"),
                                           formatRemainingTime(remainingBytes: totalBytes - completedBytes)))
                               : Text(String()))
                            Spacer()
                        }
                        .font(.subheadline)
                        .monospacedDigit()
                    }
                }
                .padding(.horizontal)
                Spacer()
            }
            Spacer()
        }
        .frame(width: 400, height: 200)
        .onAppear {
            startDownload()
        }
    }

    func startDownload() {
        errorMessage = nil
        fractionProgress = 0
        completedBytes = 0
        totalBytes = 0
        let url = HennyWineInstaller.runtimeTarballURL
        downloadTask = URLSession(configuration: .ephemeral).downloadTask(with: url) { fileURL, response, error in
            // Anything other than a 200 with a file is a failure; without this check a
            // 404 page would be "installed" as the runtime, and a DNS error would hang.
            let status = (response as? HTTPURLResponse)?.statusCode
            var failure: String?
            var savedURL: URL?
            if let error {
                failure = error.localizedDescription
            } else if status != 200 {
                failure = "The server returned HTTP \(status.map(String.init) ?? "no response")."
            } else if let fileURL {
                // URLSession deletes its temp file when this handler returns, so move it now.
                let destination = FileManager.default.temporaryDirectory
                    .appending(path: "HennyWine-\(UUID().uuidString).tar.gz")
                do {
                    try FileManager.default.moveItem(at: fileURL, to: destination)
                    savedURL = destination
                } catch {
                    failure = error.localizedDescription
                }
            } else {
                failure = "The download finished without a file."
            }
            Task { @MainActor [failure, savedURL] in
                if let failure {
                    errorMessage = "Couldn't download HennyWine from \(url.host() ?? url.absoluteString). \(failure)"
                } else if let savedURL {
                    tarLocation = savedURL
                    proceed()
                }
            }
        }
        observation = downloadTask?.observe(\.countOfBytesReceived) { task, _ in
            Task { @MainActor in
                let currentTime = Date()
                let elapsedTime = currentTime.timeIntervalSince(startTime ?? currentTime)
                if completedBytes > 0 {
                    downloadSpeed = Double(completedBytes) / elapsedTime
                }
                totalBytes = task.countOfBytesExpectedToReceive
                completedBytes = task.countOfBytesReceived
                if totalBytes > 0 {
                    fractionProgress = Double(completedBytes) / Double(totalBytes)
                }
            }
        }
        startTime = Date()
        downloadTask?.resume()
    }

    func formatBytes(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = true
        return formatter.string(fromByteCount: bytes)
    }

    func shouldShowEstimate() -> Bool {
        let elapsedTime = Date().timeIntervalSince(startTime ?? Date())
        return Int(elapsedTime.rounded()) > 5 && completedBytes != 0
    }

    func formatRemainingTime(remainingBytes: Int64) -> String {
        let remainingTimeInSeconds = Double(remainingBytes) / downloadSpeed

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        if shouldShowEstimate() {
            return formatter.string(from: TimeInterval(remainingTimeInSeconds)) ?? ""
        } else {
            return ""
        }
    }

    func proceed() {
        path.append(.hennyWineInstall)
    }
}
