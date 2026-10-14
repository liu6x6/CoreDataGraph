# CoreDataGraph — Core Data 关系图可视化 Mac App 设计文档

> 背景：新版 Xcode 不再显示 Core Data Model 的 Entity 关系图（Graph Editor 已被移除）。
> 目标：用 SwiftUI 开发一个 macOS App，快速、方便地可视化 `.xcdatamodeld` 中的 Entity 及其关系。
>
> 参考模型：`Cookidoo.xcdatamodeld`（21 个 Entity、32 个 Relationship、v2~v27 共 26 个版本）

---

## 一、核心思路：数据从哪来

`.xcdatamodeld` 本质是一个目录，内部每个版本是一个 `.xcdatamodel` 目录，其中 `contents` 是纯 XML 文件。有两条读取路径：

| 方案 | 做法 | 优缺点 |
|---|---|---|
| **A. `NSManagedObjectModel`** | `NSManagedObjectModel(contentsOf: url)` 直接加载 `contents` XML | ✅ 官方 API，一次拿到所有 entity / attribute / relationship / deletionRule<br>❌ 只能加载单个版本 |
| **B. 自己解析 XML** | 用 `XMLParser` 读 `contents` | ✅ 可拿到版本 hash，可 diff 多个版本<br>代码量稍多 |

**决策：A 为主（可视化），B 用于「版本对比」加分功能。**

### 加载 `.xcdatamodeld` 目录时的流程

1. 读取 `.xccurrentversion` plist，取 `_XCCurrentVersionName`（如 `Cookidoo v27.xcdatamodel`）
2. 拼出路径：`<model>.xcdatamodeld/<version>.xcdatamodel/contents`
3. 用 `NSManagedObjectModel(contentsOf:)` 加载
4. 侧边栏提供版本下拉框，可切换查看任意历史版本

---

## 二、App 架构（MVVM）

```
CoreDataGraph.app
├── Model
│   ├── ModelParser.swift        // NSManagedObjectModel → GraphModel
│   ├── GraphModel.swift         // EntityNode / RelationshipEdge 值类型
│   ├── XMLModelParser.swift     // 直接解析 contents XML（用于版本 diff）
│   └── VersionDiffer.swift      // 对比 xcdatamodeld 内多个版本
├── ViewModel
│   ├── GraphViewModel.swift     // 布局引擎 + 选中态 + 缩放/平移状态
│   └── LayoutEngine.swift       // 力导向 / 层级布局算法
└── View
    ├── ContentView.swift        // NavigationSplitView 三栏骨架
    ├── GraphCanvasView.swift    // 主画布 (ZStack: 边层 + 节点层)
    ├── EdgeLayerView.swift      // Canvas 画贝塞尔连线 + 箭头 + 标签
    ├── EntityNodeView.swift     // 单个 Entity 卡片（可拖拽）
    ├── InspectorView.swift      // 右侧详情面板
    ├── EntityListView.swift     // 左侧 Entity 列表（搜索/过滤）
    └── ToolbarView.swift        // 布局切换、版本选择、导出
```

### GraphModel（关键数据结构）

```swift
struct GraphModel {
    var nodes: [EntityNode]
    var edges: [RelationshipEdge]
    var modelName: String
    var versionName: String?
}

struct EntityNode: Identifiable {
    let id = UUID()
    let name: String
    let attributes: [AttributeInfo]       // 名称 / 类型 / optional / 默认值
    let relationships: [RelationshipInfo]
    var position: CGPoint = .zero         // 布局结果
    var isPinned: Bool = false            // 用户手动拖过就固定
    var size: CGSize = .zero              // 根据内容估算的卡片尺寸
}

struct AttributeInfo: Identifiable {
    let id = UUID()
    let name: String
    let type: String                      // String / Integer 16 / Transformable / Date ...
    let isOptional: Bool
    let customClassName: String?          // Transformable 的自定义类
}

struct RelationshipEdge: Identifiable {
    let id = UUID()
    let from: EntityNode.ID
    let to: EntityNode.ID
    let name: String
    let inverseName: String?
    let isToMany: Bool
    let deletionRule: String              // Cascade / Nullify / Deny / No Action
    let isSelfLoop: Bool                  // 自引用关系
}
```

### Parser 核心代码

```swift
enum ModelParser {
    /// url 可以是 .xcdatamodeld 目录、.xcdatamodel 目录或 contents 文件
    static func parse(contentsOf url: URL) throws -> GraphModel {
        let contentsURL = try resolveContentsURL(url)
        guard let mom = NSManagedObjectModel(contentsOf: contentsURL) else {
            throw ParseError.invalidModel
        }

        var nodes: [EntityNode] = []
        var edges: [RelationshipEdge] = []
        // 先建 name → nodeID 映射，再生成 edges ...
        for entity in mom.entities {
            let node = EntityNode(
                name: entity.name ?? "Unknown",
                attributes: entity.attributesByName.map { name, desc in
                    AttributeInfo(name: name,
                                  type: desc.attributeType.description,
                                  isOptional: desc.isOptional,
                                  customClassName: nil)
                },
                relationships: [])
            nodes.append(node)
        }
        let idByName = Dictionary(uniqueKeysWithValues: { ($1.name, $1.id) } in
            nodes.map { ($0.name, $0.id) }
        )
        for entity in mom.entities {
            for rel in entity.relationshipsByName.values {
                guard let from = idByName[entity.name ?? ""],
                      let to = idByName[rel.destinationEntity?.name ?? ""] else { continue }
                edges.append(RelationshipEdge(
                    from: from, to: to,
                    name: rel.name,
                    inverseName: rel.inverse?.name,
                    isToMany: rel.isToMany,
                    deletionRule: rel.deleteRule.description,
                    isSelfLoop: rel.destinationEntity === mom.entitiesByName[entity.name ?? ""]))
            }
        }
        return GraphModel(nodes: nodes, edges: edges,
                          modelName: url.deletingPathExtension().lastPathComponent,
                          versionName: nil)
    }
}
```

---

## 三、布局算法（最关键的部分）

21 个节点规模很小，两种布局都流畅，提供切换按钮：

### 1️⃣ 力导向布局（默认）

自写 force simulation（约 80 行，无需第三方库）：

- **斥力**：所有节点两两之间 Coulomb 斥力，防止重叠。
  节点是矩形卡片（高度随 attribute 数量变化），斥力按矩形间距而非圆形半径计算。
- **引力**：有 relationship 的节点对之间加弹簧力（Hooke），拉近相关实体。
- **向心力**：轻微地把所有节点拉向画布中心，防止发散。
- **迭代**：`Task` 循环或 `TimelineView(.animation)` 驱动，每次迭代位移 × 阻尼系数 0.9，
  约 300 次迭代或总位移小于阈值后收敛停止。
- **isPinned 的节点不参与迭代**（用户手动摆放的位置保持不动）。

```swift
func tick() {
    // 1. 斥力: 对每一对节点 (i, j)
    // 2. 弹簧力: 对每一条 edge
    // 3. position += velocity * damping; velocity *= damping
    // 4. 收敛判断: totalMovement < 0.5 → 停止
}
```

### 2️⃣ 层级布局（可切换）

按关系拓扑排序分层（类似旧 Xcode 的 Editor → Layout）：

- 入度为 0（没有别的实体指向它 / 或作为"根"实体如 `Recipe`）的放最上层
- 每向下一层，y += 层间距；同层节点按 x 均匀分布
- 对 Recipe 这种"一对多子实体"结构（`RecipeIngredientGroup`、`RecipeStepGroup`、`RecipeNutrition`…）特别清晰

---

## 四、渲染方案

**边用 `Canvas` 一次性绘制，节点用 SwiftUI View 叠加** —— 性能与交互的最佳平衡。

```swift
struct GraphCanvasView: View {
    @Bindable var vm: GraphViewModel

    var body: some View {
        ZStack {
            // 1. 边层：Canvas 画完所有线（32 条线毫无压力）
            Canvas { ctx, size in
                for edge in vm.visibleEdges {
                    let a = vm.anchorPoint(of: edge.from, toward: edge.to)  // 卡片边缘交点
                    let b = vm.anchorPoint(of: edge.to, toward: edge.from)
                    var path = Path()
                    path.move(to: a)
                    path.addQuadCurve(to: b, control: vm.controlPoint(a, b))

                    ctx.stroke(path,
                        with: .color(vm.isHighlighted(edge) ? .accentColor : .gray.opacity(0.6)),
                        style: .init(lineWidth: vm.isHighlighted(edge) ? 2.5 : 1.5))
                    // 箭头：单箭头 = to-one；双箭头 = to-many
                    // 中点标签："recipes (Cascade)"
                }
            }

            // 2. 节点层
            ForEach(vm.nodes) { node in
                EntityNodeView(node: node,
                               isSelected: vm.selectedID == node.id,
                               isDimmed: vm.selectedID != nil && !vm.isNeighbor(of: node))
                    .position(node.position)
                    .gesture(vm.dragGesture(for: node))
                    .onTapGesture { vm.selectedID = node.id }
            }
        }
        .scaleEffect(vm.zoom, anchor: .center)
        .offset(vm.pan)
        .gesture(vm.canvasMagnification)   // 触控板捏合缩放
        .simultaneousGesture(vm.canvasPan) // 空白处拖动平移
        .background(.background)
        .onTapGesture { vm.selectedID = nil }  // 点空白取消选中
    }
}
```

### EntityNodeView（模仿旧 Xcode 风格卡片）

```
┌────────────────────────┐
│ Recipe            ⌄    │  ← 标题栏（选中时 accent 高亮）
├────────────────────────┤
│ id: String             │
│ title: String          │  ← attributes（默认折叠只显示前 5 条，
│ difficulty: Int16      │     点击 ⌄ 展开全部）
│ …                      │
├────────────────────────┤
│ ◆ stepGroupsUnordered →│  ← relationships 区块，
│ ◆ tagsUnordered →      │     点击可高亮/跳转到目标 entity
└────────────────────────┘
```

- 卡片宽度固定 ~220pt，高度按内容计算并写回 `node.size`（供布局斥力使用）
- 非邻居节点 `opacity(0.25)` 实现聚焦效果

### 窗口结构

```swift
NavigationSplitView {
    EntityListView(vm: vm)       // 左：entity 列表 + 搜索
} detail: {
    HSplitView {
        GraphCanvasView(vm: vm)  // 中：画布
        InspectorView(vm: vm)    // 右：详情面板
    }
}
```

---

## 五、交互设计（"快速方便"的关键）

| # | 交互 | 行为 |
|---|---|---|
| 1 | **点击 Entity** | 右侧 Inspector 显示完整属性/关系；画布上只高亮直接邻居，其余半透明（理解 Recipe 这种 8 个关系的核心节点极其有用）|
| 2 | **双击 Relationship 标签** | 高亮两端 entity，弹出 inverse、deletion rule、min/max count |
| 3 | **拖拽节点** | 手动微调布局，松手后 `isPinned = true`；右键可 unpin |
| 4 | **搜索框**（⌘F）| 按 entity / attribute 名过滤，如搜 "markedForDeletion" 看哪些实体有软删除 |
| 5 | **双击空白 / ⌘0** | 缩放到适配全部内容（zoom to fit）|
| 6 | **左侧列表点击** | 画布居中滚动到该 entity 并选中 |

### 打开文件的方式

1. **标准方式**：注册为 `.xcdatamodeld` 的编辑器/查看器（`Info.plist` 的 `CFBundleDocumentTypes`），Finder 里右键 "Open With"，或 App 内 ⌘O
2. **拖拽**：把 `.xcdatamodeld` 拖到窗口（`.onDrop` / `DropDelegate`）
3. **⭐ 自动刷新（体验最爽）**：`@AppStorage` 记住上次打开的路径；用
   `DispatchSource.makeFileSystemObjectSource(fileDescriptor:events: .write)`
   watch 该目录，Xcode 里一保存模型，App 画布自动重新解析刷新

### 导出

- **PNG**：`ImageRenderer` 渲染整个画布
- **Graphviz DOT**：文本导出，可用 `dot -Tsvg` 二次处理
- **Mermaid ER 图**：`erDiagram` 语法文本，直接贴进 Markdown / 语雀 / GitHub 文档

---

## 六、加分功能：版本 Diff

模型有 v2~v27 共 26 个版本，这是 Xcode 图形界面从来没有过的能力：

1. 工具栏选择两个版本（如 v26 vs v27）
2. 分别用 XML 解析（方案 B）得到两套 GraphModel
3. Diff 并在画布上着色：
   - 🟢 绿色 = 新增 entity / attribute / relationship
   - 🔴 红色 = 删除
   - 🟡 黄色 = 修改（类型变化、optional 变化、deletion rule 变化）
4. 右侧 Inspector 列出完整 diff 清单
5. 用途：**检查 lightweight migration 是否遗漏、review 数据库变更**

---

## 七、技术选型总结

| 项 | 选择 |
|---|---|
| 最低系统 | macOS 14+（Canvas / ImageRenderer / @Observable 均成熟）|
| 状态管理 | `@Observable`（Observation framework）+ `@Bindable` |
| 布局 | 自写力导向 + 层级布局（~150 行），**无第三方依赖** |
| 渲染 | Canvas（边）+ SwiftUI View（节点）混合 |
| 窗口 | `NavigationSplitView` 三栏 |
| 解析 | `NSManagedObjectModel`（主）+ `XMLParser`（diff 用）|
| 文件监听 | `DispatchSource` file system object source |
| 依赖 | **零第三方依赖** |

### 工作量估计

| 里程碑 | 内容 | 预估 |
|---|---|---|
| MVP | 打开 + 解析 + 力导向布局 + 画布渲染 + Inspector | 600~800 行，一个下午 |
| V1.1 | 层级布局、搜索、自动刷新、导出 PNG/DOT/Mermaid | +300 行 |
| V1.2 | 版本 Diff | +300 行 |

---

## 八、下一步

1. Xcode 新建 macOS SwiftUI App 项目 `CoreDataGraph`（Deployment Target: macOS 14）
2. 按第二节目录结构创建文件
3. 先实现 `ModelParser` + `GraphViewModel`，用 Cookidoo v27 模型验证解析正确性
4. 实现力导向布局 + 画布渲染，跑通 MVP
5. 迭代交互与加分功能
