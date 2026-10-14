# 架构

## 工程形态

- Xcode 16+ 工程，**PBXFileSystemSynchronizedRootGroup**：`CoreDataGraph/` 源码目录下新增文件自动入 target，**无需改 pbxproj**
- `GENERATE_INFOPLIST_FILE = YES` + `INFOPLIST_FILE = SupportingFiles/Info.plist`（合并；文档类型注册在该 plist）
- 构建设置关键点：`MACOSX_DEPLOYMENT_TARGET=26.2`、`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`、`SWIFT_VERSION=5.0`、`ENABLE_USER_SELECTED_FILES = readwrite`（NSSavePanel 必需）
- 零第三方依赖

## 目录与职责

```
CoreDataGraph/
├── CoreDataGraphApp.swift      # @main、AppDelegate(open事件/Dock菜单)、菜单命令(⌘O/⌘Z/⌘Z/0/⇧⌘L/面板开关)、Settings scene、OpenRecentMenu
├── ContentView.swift           # 三栏 HStack 骨架(自管理, 非NavigationSplitView)、工具栏、fileImporter/drop、状态toast、CompareButton/ComparePanel
├── Model/
│   ├── GraphModel.swift        # AttributeInfo/RelationshipInfo/FetchIndexInfo/EntityNode/RelationshipEdge/InheritanceLink/ModelVersion/GraphDocument + NodeMetrics(全局尺寸中枢)
│   ├── ContentsXMLParser.swift # contents XML → ParsedModelDocument（含 <elements> 旧排版坐标）
│   ├── ModelLoader.swift       # URL 分发(xcdatamodeld/xcdatamodel/contents/mom/momd)、版本枚举(.xccurrentversion)、MOM 兜底转换
│   └── ModelDiffer.swift       # 两 ParsedModelDocument → ModelDiff(实体/属性/关系三级变更)
├── ViewModel/
│   ├── GraphViewModel.swift    # 核心状态机：open/版本/diff/图构建/选择/框选/缩放平移/布局调度/undo栈/排版保存/文件监听/restoreLastDocument
│   └── LayoutEngine.swift      # LayoutMode 枚举 + applySaved/forceDirected/hierarchical/resolveOverlaps
├── Views/
│   ├── GraphCanvasView.swift   # 画布：Canvas边层+卡片层+marquee覆盖层；手势(框选/⌥平移/拖动/捏合/滚动监听)；Notification 接收(zoomToFit/relayout/settingsChanged)
│   ├── GraphDrawing.swift      # 边绘制纯函数：inverse去重、route()正交路由、箭头四样式、继承空心三角、标签避让；被 Canvas 与 SVGExporter 共用
│   ├── EntityNodeView.swift    # Xcode 风格卡片；组/选中/diff 行级着色；context menu
│   ├── SidebarView.swift       # 版本Picker/搜索/实体List(单击选中双击fly-to)/diff摘要
│   ├── InspectorView.swift     # EntityInspector / DiffInspector / ModelOverviewInspector(+提示文案)
│   ├── WelcomeView.swift       # 空态+最近打开
│   └── SettingsView.swift      # 设置窗口 UI（绑定 AppSettings）
└── Helpers/
    ├── AppSettings.swift       # @Observable 单例 + UserDefaults；Color hex 扩展；ArrowStyle 枚举；NodeMetrics.scale/baseWidth 注入
    ├── PositionStore.swift     # 自定义排版 [模型路径#版本] → {entity: CGPoint}
    ├── RecentFilesStore.swift  # 最近文件 security-scoped bookmarks + lastOpened
    ├── OpenRouter.swift        # AppleEvent/Dock/菜单打开请求 → 活动窗口 vm（weak）或 pendingURL
    ├── DirectoryWatcher.swift  # GCD DispatchSource 文件监听
    ├── Exporter.swift          # NSSavePanel + PNG(ImageRenderer)/文本导出 + SnapshotView(导出用画布)
    └── SVGExporter.swift       # 纯矢量 SVG 渲染（复用 GraphDrawing.route/borderPoint/arrowExtent）
SupportingFiles/Info.plist      # CFBundleDocumentTypes + UTImportedTypeDeclarations(自有前缀 com.selflearn.coredatagraph.*)
```

## 核心数据流

```
open(url) ─ ModelLoader.load ─ ContentsXMLParser ─ GraphDocument{versions, document}
      │
      ├─ rebuildGraph():  (diff模式? 解析old/new两文档 : 当前文档)
      │     → nodes[EntityNode] + edges[RelationshipEdge](inverse对去重在绘制层做) + inheritanceLinks
      │     → applyLayout(initial:)  优先级: PositionStore记忆 > XML<elements> > force
      │     → needsZoomToFit = true
      │
      └─ GraphCanvasView 观察 vm → Canvas(GraphDrawing.draw) + ForEach(EntityNodeView)
```

## 关键设计决策（为什么）

1. **不用 NavigationSplitView**：其列宽协商与内嵌 HSplitView 冲突导致过布局错乱；改自管理 HStack + 两个独立开关（@AppStorage 持久化）
2. **整图等比缩放**：Canvas 用 `ctx.translateBy+scaleBy` 画世界坐标，卡片 `.scaleEffect(zoom)`；否则缩放时固定尺寸卡片必然互叠
3. **inverse 关系对合并为一条线**：在 `GraphDrawing.draw` 内按 id 字典序去重；两端箭头各自表达本端基数；标签源端=关系名、目标端=inverse名
4. **行级锚点**：连线从卡片"关系行"的左右边缘引出（`NodeMetrics.relRowOffset`），复刻 Xcode
5. **NodeMetrics 是尺寸唯一真源**：布局、绘制、命中、SVG 全部经由它；`scale`(字体)与 `baseWidth`(宽度)由 AppSettings 注入

## 并发模型

- 全 target 默认 MainActor；XMLParser delegate / DispatchSource handler 均回主线程
- `DirectoryWatcher` 为 nonisolated class，handler 内 `DispatchQueue.main.async` 语义（handler 由 vm 提供，vm 是 MainActor）
- fly-to 补间与 undo 均为 vm 内 Task/同步操作，无后台线程
