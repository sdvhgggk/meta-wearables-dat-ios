import Foundation
import Observation

struct ProMediaItem: Identifiable, Sendable {
  let url: URL
  let date: Date
  let size: Int64
  var id: String { url.lastPathComponent }
  var isVideo: Bool { url.pathExtension == "mov" || url.pathExtension == "mp4" }
}

// Serial disk operations keep copying recordings and enumerating the library off the UI actor.
actor ProMediaDisk {
  let directory: URL

  init(directory: URL) { self.directory = directory }

  func list() throws -> [ProMediaItem] {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey], options: .skipsHiddenFiles)
      .filter { ["jpg", "mov", "mp4"].contains($0.pathExtension) }
      .map { try item(at: $0) }
      .sorted { $0.date > $1.date }
  }

  func savePhoto(_ data: Data) throws -> ProMediaItem {
    let url = try destination(extension: "jpg")
    try data.write(to: url, options: .atomic)
    return try item(at: url)
  }

  func saveVideo(_ source: URL) throws -> ProMediaItem {
    let url = try destination(extension: source.pathExtension == "mp4" ? "mp4" : "mov")
    let staging = directory.appendingPathComponent(".\(UUID().uuidString).partial")
    defer { try? FileManager.default.removeItem(at: staging) }
    try FileManager.default.copyItem(at: source, to: staging)
    try FileManager.default.moveItem(at: staging, to: url)
    return try item(at: url)
  }

  private func destination(extension ext: String) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
  }

  private func item(at url: URL) throws -> ProMediaItem {
    let values = try url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
    return ProMediaItem(url: url, date: values.creationDate ?? .distantPast, size: Int64(values.fileSize ?? 0))
  }
}

@MainActor @Observable
final class ProMediaLibrary {
  private(set) var items: [ProMediaItem] = []
  private(set) var errorMessage: String?
  @ObservationIgnored private let disk: ProMediaDisk

  init(directory: URL = URL.documentsDirectory.appendingPathComponent("SHHQ Media", isDirectory: true)) {
    disk = ProMediaDisk(directory: directory)
  }

  func load() async {
    do {
      let loaded = try await disk.list()
      // Merge with captures saved while this read was suspended.
      var byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
      for item in loaded { byID[item.id] = item }
      items = byID.values.sorted { $0.date > $1.date }
      errorMessage = nil
    } catch { errorMessage = "Не удалось прочитать медиатеку: \(error.localizedDescription)" }
  }

  func savePhoto(_ data: Data) async throws {
    let item = try await disk.savePhoto(data)
    insert(item)
  }

  func saveVideo(_ url: URL) async throws {
    let item = try await disk.saveVideo(url)
    insert(item)
  }

  private func insert(_ item: ProMediaItem) {
    items.removeAll { $0.id == item.id }
    items.insert(item, at: 0)
    errorMessage = nil
  }
}
