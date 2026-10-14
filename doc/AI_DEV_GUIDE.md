# AI 开发指南（必读）

## 构建与验证

```bash
# 编译（唯一权威验证）
cd /Users/xiaolong/Documents/work/CoreDataGraph/CoreDataGraph && \
xcodebuild -project CoreDataGraph.xcodeproj -scheme CoreDataGraph -configuration Debug build 2>&1 | grep -E "error:|BUILD"

# 离线逻辑验证 harness（不启动 GUI）：编译除 CoreDataGraphApp.swift 外全部源码 + main.swift
cd /tmp && cat > main.swift <<'EOF'
import Foundation
import AppKit
let vm = GraphViewModel()
vm.open(url: URL(fileURLWithPath: "<model>.xcdatamodeld 或 .xcdatamodel"))
print(vm.nodes.count, vm.edges.count, vm.inheritanceLinks.count)
EOF
SRC=/Users/xiaolong/Documents/work/CoreDataGraph/CoreDataGraph/CoreDataGraph
xcrun swiftc -O -o harness $(find "$SRC" -name "*.swift" ! -name "CoreDataGraphApp.swift") main.swift && ./harness
```
- 测试模型：`/Users/xiaolong/Documents/Pro/Cookido.cn-RN_Put/cookidoo-rn/ios/CookidooDependenciesPackage/Sources/CookidooFoundation/Persistance/CoreData/Cookidoo.xcdatamodeld`（27 版本、21 实体、32 关系、无 parentEntity、无 <elements>）
- 合成继承模型：`/tmp/inhmodel/Test.xcdatamodel`（BaseItem←FoodItem/DrinkItem）
- **用户实例常挂 Xcode 调试器（ps stat=SX，kill -9 无效）**：不要尝试替他重启 App；编译通过即交付，提醒用户 Stop+⌘R
- 新增源文件放 `CoreDataGraph/` 源码目录即自动入 target（FileSystemSynchronized），**不要改 pbxproj**（除非 build settings）

## macOS 26 SDK 陷阱（踩过的坑）

1. `NSManagedObjectModel.entities` 与同名方法重载歧义 → 用 `entitiesByName.values`
2. `NSRelationshipDescription.inverse` 已改名 **`inverseRelationship`**（`inverse` 是方法）
3. `NSAttributeDescription` 无 `usesScalarValueType` 公开属性；无 `externalStorageBinaryDataAttributeType` case（switch 用 `default:`）
4. `URL(resolvingBookmarkData:options:relativeTo:bookmarkDataIsStale:)` 的 stale 参数是 **inout Bool**（非 ObjCBool、非可选）
5. `CommandGroupPlacement` 无 `.openRecent/.openSave/.about/.privacyPolicy/.textSize/.windowArrangements`；可用：appInfo/newItem/importExport/printItem/sidebar/windowSize/windowList/help/appSettings/appTermination/undoRedo/textEditing/textFormatting/pasteboard/toolbar/systemServices。Open Recent 子菜单用 `CommandGroup(after:.newItem){ Menu("Open Recent"){...} }`
6. `StrokeStyle(lineWidth:lineCap:lineJoin:)` 参数顺序 lineCap 在前
7. ShapeStyle 三元混用（`.primary.opacity(x) : .primary`）编译失败 → 统一 `.primary.opacity(cond ? a : b)`
8. `Optional<DiffStatus>` switch 需显式 `.some(.added)` / `.some(.none), .none`（DiffStatus 自身有 .none 会歧义）
9. 字典默认值 `?? []` 对 `[K:V]` 报 "use [:]" → `?? [:]`
10. 顶层语句 harness 文件名必须 `main.swift`
11. BFS 分层**必须 visited 判定**（relaxation 版遇环无限循环）
12. Canvas 闭包内读 @Observable 不保证触发重绘 → body 层取局部变量（见 RENDERING.md）

## 代码约定

- 全 target 默认 MainActor；新类型无需标注
- MEMBER_IMPORT_VISIBILITY：显式 `import Observation / AppKit / UniformTypeIdentifiers / CoreData`
- 尺寸/字体只经 `NodeMetrics`（scale 与 baseWidth 由 AppSettings 注入）；**禁止在 View 里硬编码卡片尺寸**
- 设置项配方：AppSettings 加属性(didSet 存 defaults + applyMetrics/postChanged) → Keys + register + init + resetToDefaults → SettingsView 控件 → 消费方读 AppSettings.shared
- 箭头样式配方：ArrowStyle 加 case(+shortName) → GraphDrawing.drawArrowHead/arrowExtent 加分支 → SVGExporter.arrowSVG 加分支 → SettingsView 自动出现（segmented+预览）
- 通知名集中在 GraphCanvasView 的 `extension Notification.Name`
- 状态提示统一 `vm.statusMessage`（ContentView 底部 toast 自动消失）

## 常见任务路线

| 任务 | 改哪里 |
|---|---|
| 新布局算法 | LayoutEngine 加 static + LayoutMode case + vm.applyLayout switch |
| 新卡片信息行 | GraphModel 字段 + ContentsXMLParser 解析 + NodeMetrics.size + EntityNodeView + SVGExporter |
| 新手势 | GraphCanvasView（注意与 marquee/pan 分流逻辑共存）|
| 新 diff 维度 | ModelDiffer + buildDiffLookups + EntityNodeView/SVG 着色 |
| 打开新文件类型 | ModelLoader.load 分支 + Info.plist extensions + allowedTypes(ContentView) |

## 回归检查清单（改渲染/布局后）

1. xcodebuild 通过
2. harness：nodes/edges/inheritance 数量正确、force 布局 overlaps=0、span 合理
3. SVG：xmllint 通过
4. 提醒用户 Stop+⌘R 目视：缩放不重叠、线不压卡片、标签不压箭头、设置即时生效
