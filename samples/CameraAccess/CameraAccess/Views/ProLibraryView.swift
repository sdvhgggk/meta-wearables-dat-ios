import AVKit
import SwiftUI

struct ProLibraryView: View {
  var library: ProMediaLibrary
  @State private var selected: ProMediaItem?
  @State private var filter = "all"

  private var filtered: [ProMediaItem] {
    library.items.filter { filter == "all" || ($0.isVideo ? "video" : "photo") == filter }
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Picker("Тип файлов", selection: $filter) {
          Text("Все").tag("all")
          Text("Фото").tag("photo")
          Text("Видео").tag("video")
        }.pickerStyle(.segmented).padding()
        if let error = library.errorMessage {
          Text(error).foregroundStyle(.red).padding()
          Button("Повторить") { Task { await library.load() } }
        }
        if filtered.isEmpty {
          ContentUnavailableView("Здесь будут твои кадры", systemImage: "photo.stack", description: Text("Сними фото или запиши видео во вкладке «Камера»."))
        } else {
          List(filtered) { item in
            Button { selected = item } label: {
              HStack(spacing: 16) {
                Image(systemName: item.isVideo ? "play.rectangle.fill" : "photo.fill")
                  .font(.title).foregroundStyle(.mint).frame(width: 44)
                VStack(alignment: .leading, spacing: 5) {
                  Text(item.isVideo ? "Видео" : "Фото").foregroundStyle(.primary)
                  Text(item.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                  .font(.caption).foregroundStyle(.secondary)
              }.padding(.vertical, 6)
            }
          }.listStyle(.plain)
        }
      }
      .navigationTitle("Медиатека")
      .refreshable { await library.load() }
      .sheet(item: $selected) { item in ProMediaDetail(item: item) }
    }
  }
}

private struct ProMediaDetail: View {
  let item: ProMediaItem
  @Environment(\.dismiss) private var dismiss
  @State private var player: AVPlayer?
  @State private var photo: UIImage?
  @State private var failed = false

  var body: some View {
    NavigationStack {
      Group {
        if item.isVideo, let player { VideoPlayer(player: player) }
        else if let photo { Image(uiImage: photo).resizable().scaledToFit() }
        else if failed { Text("Не удалось открыть файл") }
        else { ProgressView() }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.black)
      .navigationTitle(item.isVideo ? "Видео" : "Фото")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { Button("Готово") { dismiss() } }
        ToolbarItem(placement: .topBarTrailing) { ShareLink(item: item.url) { Label("Поделиться", systemImage: "square.and.arrow.up") } }
      }
      .task {
        if item.isVideo { player = AVPlayer(url: item.url); player?.play() }
        else {
          let url = item.url
          let data = await Task.detached { try? Data(contentsOf: url) }.value
          photo = data.flatMap { UIImage(data: $0) }
          failed = photo == nil
        }
      }
      .onDisappear { player?.pause() }
    }.preferredColorScheme(.dark)
  }
}
