# 导出（Helpers/Exporter.swift + SVGExporter.swift）

统一入口：`Exporter.askSaveURL(name:types:)`（NSSavePanel，readwrite 权限）→ 写文件 → statusMessage。

## PNG

- `SnapshotView`（世界坐标平移至原点、zoom=1、interactive=false 的画布副本）→ `ImageRenderer(scale: 2)` → NSBitmapImageRep PNG
- 遵循当前设置（线宽/箭头/标签/类型显隐/选中色）

## SVG（纯矢量）

- `SVGExporter.string(vm:)`：worldBounds(inset:40) 为 viewBox，平移至原点
- **与画布共用几何**：`GraphDrawing.route/borderPoint/arrowExtent` 保证像素一致
- 元素：白底 → 边(path 圆角 Q) + 箭头(四样式 path) + 标签(rect 芯片+text) → 继承线+空心三角 → 卡片(rect+header path+rows text+分隔 line+diff 圆点/删除线)
- 文本 `esc()` 转义；字体 Helvetica/Arial；尺寸取 NodeMetrics（含 scale/baseWidth）
- 验证：`xmllint --noout` 通过

## Mermaid

- `erDiagram`：实体块（属性≤30，类型空格→下划线）+ 关系行 `A ||--o{ B : "name [rule]"`（toMany/optional 映射基数符）

## DOT

- digraph + record 节点（属性行 \l）+ 边 label 含 deletionRule；to-many `arrowhead=crow`；Cascade 边红色；diff 状态 fillcolor

## 添加新导出格式配方

1. Exporter 加 `exportXXX(vm:)`（askSaveURL + 生成文本/数据）
2. ContentView 导出 Menu 加 Button
3. 本文档补一节
