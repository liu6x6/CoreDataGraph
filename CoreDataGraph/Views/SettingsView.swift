//
//  SettingsView.swift
//  CoreDataGraph
//

import SwiftUI

struct SettingsView: View {
    @Bindable var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("字体大小")
                        .frame(width: 90, alignment: .leading)
                    Slider(value: $settings.cardFontScale, in: 0.8...1.6, step: 0.05)
                    Text("\(Int(settings.cardFontScale * 100))%")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 48, alignment: .trailing)
                }
                Text("卡片与连线标签随比例缩放，卡片尺寸自动重算")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("卡片宽度")
                        .frame(width: 90, alignment: .leading)
                    Slider(value: $settings.cardWidth, in: 150...400, step: 5)
                    Text("\(Int(settings.cardWidth)) pt")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 56, alignment: .trailing)
                }
                Text("最小 150pt；改变后自动重算布局防重叠")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("卡片上显示属性类型", isOn: $settings.showAttributeTypes)
            } header: {
                Text("卡片")
            }

            Section {
                HStack {
                    Text("线条粗细")
                        .frame(width: 90, alignment: .leading)
                    Slider(value: $settings.edgeLineWidth, in: 0.5...4.0, step: 0.1)
                    Text(String(format: "%.1f pt", settings.edgeLineWidth))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 56, alignment: .trailing)
                }

                Picker("箭头样式", selection: $settings.arrowStyle) {
                    ForEach(ArrowStyle.allCases) { style in
                        Text(style.shortName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .help("空心=Xcode风格；线条= → / ⇒；to-many 均为双箭头/双标记")

                HStack(spacing: 16) {
                    ArrowPreview(style: .hollow, label: "to-one / to-many")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

                Toggle("显示连线上的关系名标签", isOn: $settings.showEdgeLabels)
            } header: {
                Text("连线")
            }

            Section {
                ColorPicker("卡片选中颜色", selection: nodeColorBinding, supportsOpacity: false)
                ColorPicker("连线选中颜色", selection: edgeColorBinding, supportsOpacity: false)
                Text("选中实体时卡片标题栏/边框与关联连线的颜色")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("颜色")
            }

            Section {
                Picker("滚动平移方向", selection: $settings.scrollPanReversed) {
                    Text("自然（跟随手指）").tag(false)
                    Text("反向").tag(true)
                }
                .pickerStyle(.segmented)
                Text("双指滚动时画布的移动方向")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("画布")
            }

            Section {
                HStack {
                    Spacer()
                    Button("恢复默认值") { settings.resetToDefaults() }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding(.bottom, 8)
    }

    private var nodeColorBinding: Binding<Color> {
        Binding(get: { settings.selectedNodeColor },
                set: { settings.selectedNodeColorHex = $0.hexString })
    }

    private var edgeColorBinding: Binding<Color> {
        Binding(get: { settings.selectedEdgeColor },
                set: { settings.selectedEdgeColorHex = $0.hexString })
    }
}

/// Live preview of the current arrow style
struct ArrowPreview: View {
    let style: ArrowStyle
    let label: String
    @Bindable var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 8) {
            Text("1:1")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Canvas { ctx, size in
                drawSample(ctx: ctx, size: size, isToMany: false)
            }
            .frame(width: 60, height: 20)
            Text("1:N")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Canvas { ctx, size in
                drawSample(ctx: ctx, size: size, isToMany: true)
            }
            .frame(width: 60, height: 20)
        }
    }

    private func drawSample(ctx: GraphicsContext, size: CGSize, isToMany: Bool) {
        let y = size.height / 2
        var line = Path()
        line.move(to: CGPoint(x: 2, y: y))
        line.addLine(to: CGPoint(x: size.width - 12, y: y))
        ctx.stroke(line, with: .color(.secondary),
                   style: StrokeStyle(lineWidth: CGFloat(settings.edgeLineWidth)))
        GraphDrawing.drawArrowHead(ctx: ctx,
                                   tip: CGPoint(x: size.width - 2, y: y),
                                   angle: 0,
                                   isToMany: isToMany,
                                   color: .secondary,
                                   width: CGFloat(settings.edgeLineWidth),
                                   style: settings.arrowStyle)
    }
}
