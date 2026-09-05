import SwiftUI

struct HistoryView: View {
  @ObservedObject var model: AppModel

  @State private var selectedArchiveID: UUID?
  @State private var confirmsDeletion = false
  @State private var exportDocument: MarkdownDocument?
  @State private var exportFilename = "Keep3-导出.md"
  @State private var isExporting = false
  @State private var exportMessage: String?
  @State private var hoveredArchiveID: UUID?
  @FocusState private var focusedArchiveID: UUID?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HSplitView {
      sidebar
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)

      detail
        .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(minWidth: 720, minHeight: 520)
    .onAppear(perform: repairSelection)
    .onChange(of: model.state.archivedItems.map(\.id)) {
      repairSelection()
    }
    .fileExporter(
      isPresented: $isExporting,
      document: exportDocument,
      contentType: MarkdownDocument.contentType,
      defaultFilename: exportFilename
    ) { result in
      handleExportResult(result)
    }
    .accessibilityIdentifier("history.root")
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("历史记录")
            .font(.title2)
            .fontWeight(.semibold)
          Text("不再占据当前注意力的事项")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Button("导出全部", systemImage: "square.and.arrow.up") {
          beginCompleteExport()
        }
        .accessibilityIdentifier("history.exportAll")
      }

      Divider()

      if model.state.archivedItems.isEmpty {
        ContentUnavailableView {
          Label("还没有历史记录", systemImage: "archivebox")
        } description: {
          Text("归档的事项会按时间保存在这里。")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(spacing: 6) {
            ForEach(model.state.archivedItems) { archivedItem in
              historyButton(archivedItem)
            }
          }
        }
      }

      if let message = exportMessage {
        Label(message, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityLabel("导出错误：\(message)")
          .accessibilityIdentifier("history.exportError")
          .id(message)
          .transition(transientMessageTransition)
      }

      if let message = model.editorMessage {
        Text(message)
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityLabel("历史记录错误：\(message)")
          .id(message)
          .transition(transientMessageTransition)
      }
    }
    .padding(20)
  }

  @ViewBuilder
  private var detail: some View {
    if let archivedItem = selectedArchivedItem {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          VStack(alignment: .leading, spacing: 6) {
            Text("历史快照")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(archivedItem.item.title)
              .font(.title2)
              .fontWeight(.semibold)
              .textSelection(.enabled)
            Text(
              archivedItem.archivedAt,
              format: .dateTime
                .year().month().day().hour().minute().second()
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityLabel(
              "归档时间，\(archivedItem.archivedAt.formatted())"
            )
          }

          if !archivedItem.item.details.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              Text("说明")
                .font(.headline)
              Text(archivedItem.item.details)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
          }

          if !archivedItem.item.subitems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
              Text("补充说明")
                .font(.headline)
              ForEach(
                Array(archivedItem.item.subitems.enumerated()),
                id: \.offset
              ) { _, subitem in
                Label(subitem, systemImage: "circle.fill")
                  .labelStyle(.titleAndIcon)
                  .font(.body)
                  .textSelection(.enabled)
              }
            }
          }

          Divider()

          HStack {
            Button("导出这一条", systemImage: "square.and.arrow.up") {
              beginExport(archivedItem)
            }
            .accessibilityIdentifier("history.exportSelected")

            Spacer()

            Button("永久删除", systemImage: "trash", role: .destructive) {
              confirmsDeletion = true
            }
            .accessibilityIdentifier("history.delete")
          }
        }
        .padding(28)
      }
      .confirmationDialog(
        "永久删除“\(archivedItem.item.title)”？",
        isPresented: $confirmsDeletion
      ) {
        Button("永久删除", role: .destructive) {
          model.removeArchivedItem(id: archivedItem.id)
        }
        .accessibilityIdentifier("history.confirmDelete")
        Button("取消", role: .cancel) {}
          .accessibilityIdentifier("history.cancelDelete")
      } message: {
        Text("删除后无法恢复。")
      }
      .accessibilityIdentifier("history.detail")
    } else {
      ContentUnavailableView {
        Label("选择一条历史记录", systemImage: "archivebox")
      } description: {
        Text("历史快照只能查看、导出或永久删除。")
      }
    }
  }

  private var selectedArchivedItem: ArchivedFocusItem? {
    guard let selectedArchiveID else {
      return nil
    }
    return model.state.archivedItems.first { $0.id == selectedArchiveID }
  }

  private func historyButton(_ archivedItem: ArchivedFocusItem) -> some View {
    Button {
      selectedArchiveID = archivedItem.id
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        Text(archivedItem.item.title)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text(
          archivedItem.archivedAt,
          format: .dateTime
            .year().month().day().hour().minute()
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      .padding(8)
      .contentShape(Rectangle())
      .background(
        rowBackground(for: archivedItem)
      )
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(alignment: .leading) {
        if selectedArchiveID == archivedItem.id {
          Capsule()
            .fill(Color("AccentColor"))
            .frame(width: 3)
            .padding(.vertical, 6)
        }
      }
      .overlay {
        if focusedArchiveID == archivedItem.id {
          RoundedRectangle(cornerRadius: 6)
            .stroke(.primary.opacity(0.46), lineWidth: 1)
        }
      }
    }
    .buttonStyle(SidebarRowPressButtonStyle())
    .focused($focusedArchiveID, equals: archivedItem.id)
    .onHover { isHovered in
      hoveredArchiveID = isHovered ? archivedItem.id : nil
    }
    .accessibilityAddTraits(
      selectedArchiveID == archivedItem.id ? .isSelected : []
    )
    .accessibilityIdentifier("history.item.\(archivedItem.id.uuidString)")
    .accessibilityLabel(
      "\(archivedItem.item.title)，归档于 \(archivedItem.archivedAt.formatted())"
    )
  }

  private func repairSelection() {
    if let selectedArchiveID,
      model.state.archivedItems.contains(where: { $0.id == selectedArchiveID })
    {
      return
    }
    selectedArchiveID = model.state.archivedItems.first?.id
  }

  private func rowBackground(
    for archivedItem: ArchivedFocusItem
  ) -> Color {
    if selectedArchiveID == archivedItem.id {
      return Color("AccentColor").opacity(0.14)
    }
    if hoveredArchiveID == archivedItem.id {
      return Color.primary.opacity(0.055)
    }
    return .clear
  }

  private var transientMessageTransition: AnyTransition {
    .asymmetric(
      insertion: .opacity.animation(
        InteractionMotion.strongEaseOut(
          duration:
            reduceMotion
            ? InteractionMotion.reducedMotionDuration
            : InteractionMotion.stateChangeDuration
        )
      ),
      removal: .opacity.animation(
        InteractionMotion.strongEaseOut(
          duration: InteractionMotion.transientExitDuration
        )
      )
    )
  }

  private func beginCompleteExport() {
    beginExport(
      document: MarkdownDocument(
        text: MarkdownExporter().complete(state: model.state)
      ),
      filename: "Keep3-导出.md"
    )
  }

  private func beginExport(_ archivedItem: ArchivedFocusItem) {
    beginExport(
      document: MarkdownDocument(
        text: MarkdownExporter().archivedItem(archivedItem)
      ),
      filename: "\(safeFilename(archivedItem.item.title))-归档.md"
    )
  }

  private func beginExport(
    document: MarkdownDocument,
    filename: String
  ) {
    exportMessage = nil
    #if DEBUG
      if ProcessInfo.processInfo.environment[
        "KEEP3_UI_TEST_EXPORT_FAILURE"
      ] == true.description {
        handleExportResult(.failure(CocoaError(.fileWriteNoPermission)))
        return
      }
    #endif
    exportFilename = filename
    exportDocument = document
    isExporting = true
  }

  private func handleExportResult(_ result: Result<URL, any Error>) {
    exportDocument = nil
    exportMessage = MarkdownExportFeedback.message(for: result)
  }

  private func safeFilename(_ title: String) -> String {
    let forbidden = CharacterSet(charactersIn: "/:")
    let components = title.components(separatedBy: forbidden)
    let joined = components.joined(separator: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return joined.isEmpty ? "Keep3" : String(joined.prefix(48))
  }
}
