# CoreDataGraph 文档索引

> 本目录是供人类与 AI 持续开发使用的工程文档。修改代码前请先读 `AI_DEV_GUIDE.md`（构建命令、SDK 陷阱、扩展配方）。

| 文档 | 内容 |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | 模块划分、核心类型、数据流、文件职责表 |
| [RENDERING.md](RENDERING.md) | 坐标系统、Canvas 渲染管线、正交路由、箭头样式、继承线、标签避让 |
| [LAYOUT.md](LAYOUT.md) | 四种布局算法（自定义记忆/原始排版/力导向/层级）与参数 |
| [INTERACTIONS.md](INTERACTIONS.md) | 手势矩阵、选择模型（单选/框选/组）、fly-to、撤销重做 |
| [DIFF.md](DIFF.md) | 任意两版本 Diff：解析、状态传播、画布/卡片行级着色 |
| [PERSISTENCE.md](PERSISTENCE.md) | 设置、排版记忆、最近文件书签、文件监听、Finder 注册 |
| [EXPORT.md](EXPORT.md) | PNG / SVG / Mermaid / DOT 四种导出实现要点 |
| [AI_DEV_GUIDE.md](AI_DEV_GUIDE.md) | **AI 开发必读**：构建/验证命令、macOS 26 SDK 陷阱、扩展配方 |
| [CHANGELOG.md](CHANGELOG.md) | 功能演进历史 |
| [CoreDataGraph-App设计文档.md](CoreDataGraph-App设计文档.md) | 最初的设计稿（历史参考） |

## 30 秒理解本项目

- **输入**：`.xcdatamodeld/.xcdatamodel/contents/.mom(d)` → `ContentsXMLParser`（XML）或 `NSManagedObjectModel`（兜底）→ `GraphModel` 值类型
- **状态**：`GraphViewModel`（@Observable，MainActor）持有 nodes/edges/inheritanceLinks/选择/缩放平移/diff
- **渲染**：`GraphCanvasView` = Canvas（世界坐标连线，ctx 缩放）+ SwiftUI 卡片（scaleEffect 同缩放）
- **布局**：`LayoutEngine`（层级种子 + 矩形碰撞力导向 / 层级换行 / XML 原始坐标 / 用户记忆）
- **持久化**：UserDefaults（设置、排版记忆、最近文件 security-scoped bookmark）
