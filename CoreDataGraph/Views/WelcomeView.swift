//
//  WelcomeView.swift
//  CoreDataGraph
//

import SwiftUI

struct WelcomeView: View {
    @Bindable var vm: GraphViewModel
    private var recents: RecentFilesStore { RecentFilesStore.shared }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, options: .repeating)

            VStack(spacing: 6) {
                Text("CoreDataGraph")
                    .font(.system(size: 24, weight: .bold))
                Text("可视化任意 Core Data 模型的实体与关系图")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            if let error = vm.loadError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: 420)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
            }

            Button {
                vm.requestFileImport = true
            } label: {
                Label("打开模型…  ⌘O", systemImage: "folder.badge.plus")
                    .frame(minWidth: 180)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            Text("支持 .xcdatamodeld / .xcdatamodel / contents / .mom(d)\n也可以直接把文件拖进窗口")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !recents.items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("最近打开")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("清除") { recents.clear() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(recents.items) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "cube.transparent")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 11))
                            Button {
                                if let url = recents.resolve(item) {
                                    vm.open(url: url)
                                } else {
                                    vm.loadError = "无法访问 \(item.name)（权限已失效，请重新打开）"
                                    recents.remove(item)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name).font(.system(size: 12))
                                    if let path = item.displayURL?.path {
                                        Text(abbreviate(path))
                                            .font(.system(size: 9))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button {
                                recents.remove(item)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.quaternary)
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .frame(maxWidth: 420)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private func abbreviate(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
