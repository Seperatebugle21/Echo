import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Settings → Back-up and restore.
struct BackupView: View {
    @AppStorage("backup.includeMusic") private var includeMusic = true
    @AppStorage("backup.justRestored") private var justRestored = false
    @State private var exportProgress: Double?
    @State private var exportedFile: URL?
    @State private var showImporter = false
    @State private var candidate: (url: URL, manifest: EchoBackup.Manifest)?
    @State private var restoreProgress: Double?
    @State private var pending: EchoBackup.Manifest?
    @State private var errorMessage: String?

    private var busy: Bool { exportProgress != nil || restoreProgress != nil }

    var body: some View {
        Form {
            if justRestored {
                Section {
                    Label("backup_restored_banner", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }

            if let pending {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("backup_pending_title", systemImage: "clock.arrow.circlepath").font(.headline)
                        Text(summary(pending)).font(.subheadline).foregroundStyle(.secondary)
                        Text("backup_pending_detail").font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("backup_restart_now") {
                        // A restore is applied at launch, so Echo has to start fresh.
                        MusicLibraryManager.shared.flushSongChanges()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
                    }
                    Button("backup_cancel_restore", role: .destructive) {
                        EchoBackup.cancelPendingRestore()
                        self.pending = nil
                    }
                }
            }

            Section {
                Toggle("backup_include_music", isOn: $includeMusic).disabled(busy)
                Button {
                    startExport()
                } label: {
                    if let exportProgress {
                        ProgressView(value: exportProgress) { Text("backup_creating") }
                    } else {
                        Label("backup_create", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(busy)
            } header: {
                Text("backup_create_header")
            } footer: {
                Text(includeMusic ? "backup_create_footer_music" : "backup_create_footer_no_music")
            }

            Section {
                Button {
                    showImporter = true
                } label: {
                    if let restoreProgress {
                        ProgressView(value: restoreProgress) { Text("backup_preparing_restore") }
                    } else {
                        Label("backup_restore", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(busy)
            } header: {
                Text("backup_restore_header")
            } footer: {
                Text("backup_restore_footer")
            }
        }
        .navigationTitle("backup_title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { pending = EchoBackup.pendingRestore() }
        .onDisappear { justRestored = false }
        .sheet(item: Binding(get: { exportedFile.map(IdentifiedURL.init) }, set: { if $0 == nil { finishExport() } })) { file in
            DocumentExporter(url: file.url) { finishExport() }.ignoresSafeArea()
        }
        .sheet(isPresented: $showImporter) {
            DocumentImporter { url in
                showImporter = false
                if let url { inspect(url) }
            }
            .ignoresSafeArea()
        }
        .alert("backup_restore_confirm_title", isPresented: Binding(get: { candidate != nil }, set: { if !$0 { candidate = nil } })) {
            Button("backup_restore_confirm_action", role: .destructive) {
                if let candidate { stage(candidate.url) }
                candidate = nil
            }
            Button("backup_cancel", role: .cancel) { candidate = nil }
        } message: {
            if let candidate {
                Text(summary(candidate.manifest) + "\n\n" + String(localized: candidate.manifest.includesMusic
                    ? "backup_restore_confirm_music" : "backup_restore_confirm_no_music"))
            }
        }
        .alert("backup_error_title", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func summary(_ manifest: EchoBackup.Manifest) -> String {
        let date = manifest.created.formatted(date: .abbreviated, time: .shortened)
        let size = ByteCountFormatter.string(fromByteCount: manifest.byteCount, countStyle: .file)
        return String(localized: "backup_summary \(date) \(manifest.songCount) \(size)")
    }

    // MARK: Export

    private func startExport() {
        let library = MusicLibraryManager.shared
        library.flushSongChanges()
        SongArtworkStore.shared.waitForWrites()
        let songCount = library.songs.count
        let music = includeMusic
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let defaults = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) }
        let stamp = Date().formatted(.iso8601.year().month().day())
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Echo-\(stamp).\(EchoBackup.fileExtension)")
        exportProgress = 0
        Task.detached(priority: .userInitiated) {
            // Give the library save above a moment to reach the disk.
            try? await Task.sleep(for: .milliseconds(600))
            do {
                try EchoBackup.export(to: file, defaults: defaults, includeMusic: music, songCount: songCount,
                                      appVersion: version) { value in
                    Task { @MainActor in if exportProgress != nil { exportProgress = value } }
                }
                await MainActor.run { exportProgress = nil; exportedFile = file }
            } catch {
                await MainActor.run { exportProgress = nil; errorMessage = error.localizedDescription }
            }
        }
    }

    private func finishExport() {
        if let exportedFile { try? FileManager.default.removeItem(at: exportedFile) }
        exportedFile = nil
    }

    // MARK: Restore

    private func inspect(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do { candidate = (url, try EchoBackup.manifest(of: url)) }
        catch { errorMessage = error.localizedDescription }
    }

    private func stage(_ url: URL) {
        restoreProgress = 0
        Task.detached(priority: .userInitiated) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let manifest = try EchoBackup.stageRestore(from: url) { value in
                    Task { @MainActor in if restoreProgress != nil { restoreProgress = value } }
                }
                await MainActor.run { restoreProgress = nil; pending = manifest }
            } catch {
                await MainActor.run { restoreProgress = nil; errorMessage = error.localizedDescription }
            }
        }
    }
}

private struct IdentifiedURL: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Lets the person save the backup to Files, iCloud Drive or another location.
private struct DocumentExporter: UIViewControllerRepresentable {
    let url: URL
    let done: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { done() }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { done() }
    }
}

private struct DocumentImporter: UIViewControllerRepresentable {
    let picked: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types = [UTType(filenameExtension: EchoBackup.fileExtension), .data].compactMap { $0 }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(picked: picked) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let picked: (URL?) -> Void
        init(picked: @escaping (URL?) -> Void) { self.picked = picked }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { picked(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { picked(nil) }
    }
}
