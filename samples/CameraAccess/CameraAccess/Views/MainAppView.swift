/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// MainAppView.swift
//
// Central navigation hub that displays different views based on DAT SDK registration and device states.
// When unregistered, shows the registration flow. When registered, shows the device selection screen
// for choosing which Meta wearable device to stream from.
//

import MWDATCore
import SwiftUI

struct MainAppView: View {
  let wearables: WearablesInterface
  var viewModel: WearablesViewModel
  @State private var camera: CameraViewModel
  @State private var library: ProMediaLibrary

  init(wearables: WearablesInterface, viewModel: WearablesViewModel) {
    self.wearables = wearables
    self.viewModel = viewModel
    let library = ProMediaLibrary()
    _library = State(initialValue: library)
    _camera = State(initialValue: CameraViewModel(wearables: wearables, mediaLibrary: library))
  }

  var body: some View {
    TabView {
      Group {
        if viewModel.registrationState == .registered {
          CameraView(viewModel: camera, wearablesVM: viewModel)
        } else { connection }
      }.tabItem { Label("Камера", systemImage: "camera.fill") }
      ProLibraryView(library: library)
        .tabItem { Label("Медиа", systemImage: "photo.stack") }
      connection.tabItem { Label("Очки", systemImage: "eyeglasses") }
      settings.tabItem { Label("Настройки", systemImage: "slider.horizontal.3") }
      diagnostics.tabItem { Label("Журнал", systemImage: "waveform.path.ecg") }
    }
    .tint(.mint)
    .preferredColorScheme(.dark)
    .task { await library.load() }
    .onChange(of: viewModel.registrationState) { _, state in
      camera.log("Регистрация: \(String(describing: state))")
      if state != .registered { camera.endSession() }
    }
  }

  private var connection: some View {
    NavigationStack {
      List {
        Section {
          VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "eyeglasses").font(.system(size: 48)).foregroundStyle(.mint)
            Text("SHHQ META PRO").font(.title.bold())
            Text("Твой взгляд. Твоя история.").foregroundStyle(.secondary)
          }.padding(.vertical, 20)
          LabeledContent("Регистрация", value: viewModel.registrationState == .registered ? "Подключено" : "Нужно подключение")
          LabeledContent("Доступно устройств", value: "\(viewModel.devices.count)")
          if viewModel.registrationState != .registered {
            Button("Подключить через Meta AI") { viewModel.connectGlasses() }
              .disabled(viewModel.registrationState == .registering)
          }
        }
        Section("Твои очки") {
          if viewModel.devices.isEmpty {
            Text("Включи очки, раскрой дужки и подключи их в Meta AI.").foregroundStyle(.secondary)
          }
          ForEach(viewModel.devices, id: \.self) { id in
            Label(wearables.deviceForIdentifier(id)?.nameOrId() ?? id, systemImage: "eyeglasses")
          }
          if viewModel.requiresFirmwareUpdate {
            Button("Обновить прошивку") { Task { await viewModel.openFirmwareUpdate() } }
          }
          if viewModel.registrationState == .registered {
            Button("Обновить DAT на очках") { Task { await viewModel.openDATGlassesAppUpdate() } }
            Button("Отключить приложение", role: .destructive) {
              camera.endSession()
              viewModel.disconnectGlasses()
            }
          }
        }
        Section("Первое подключение") {
          Text("1. Подключи очки в Meta AI и включи Developer Mode.\n2. Нажми «Подключить через Meta AI».\n3. Во вкладке «Камера» начни сессию, затем включи просмотр.")
          Text("При сворачивании приложения съёмка останавливается. Готовые снимки и видео остаются в разделе «Медиа».").foregroundStyle(.secondary)
        }
      }.navigationTitle("SHHQ Meta Pro")
    }
  }

  private var settings: some View {
    @Bindable var model = camera
    return NavigationStack {
      Form {
        Section("Видеопоток") {
          Picker("Качество", selection: $model.quality) {
            Text("Экономное · 360 × 640").tag("low")
            Text("Среднее · 504 × 896").tag("medium")
            Text("Высокое · 720 × 1280").tag("high")
          }
          Picker("Кадров в секунду", selection: $model.requestedFPS) {
            ForEach([15, 24, 30], id: \.self) { Text("\($0) FPS").tag($0) }
          }
        }.disabled(camera.hasStream || camera.isFinalizingRecording)
        Section {
          Toggle("Звук с микрофона очков", isOn: $model.includeAudioInStream)
            .disabled(camera.isRecording || camera.isFinalizingRecording)
          Text("Если Bluetooth-микрофон очков недоступен, запись продолжится без звука. Микрофон iPhone не подменяет его.").font(.footnote).foregroundStyle(.secondary)
        }
        Section("Как применяются настройки") {
          Text("Останови просмотр, выбери качество и снова включи просмотр. Фактическое качество зависит от соединения и возможностей очков.")
          Text("Фото и видео сохраняются внутри приложения. Для экспорта в «Фото» открой запись в «Медиа» и нажми «Поделиться».")
        }
      }.navigationTitle("Настройки")
    }
  }

  private var diagnostics: some View {
    NavigationStack {
      List {
        Section("Сейчас") {
          LabeledContent("Сессия", value: camera.sessionStateText)
          LabeledContent("Поток", value: camera.streamStateText)
          LabeledContent("Устройство готово", value: camera.hasActiveDevice ? "Да" : "Нет")
          LabeledContent("Микрофон iOS", value: camera.micDenied ? "Доступ запрещён" : "Не запрещён")
          LabeledContent("Файлов в медиатеке", value: "\(library.items.count)")
        }
        Section("События этого запуска") {
          if camera.events.isEmpty { Text("Событий пока нет").foregroundStyle(.secondary) }
          ForEach(camera.events) { event in
            VStack(alignment: .leading, spacing: 4) {
              Text(event.message)
              Text(event.date, style: .time).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
          }
        }
      }
      .navigationTitle("Диагностика")
      .toolbar {
        ShareLink(item: camera.diagnosticReport) { Image(systemName: "square.and.arrow.up") }
          .accessibilityLabel("Экспорт журнала")
      }
    }
  }
}
