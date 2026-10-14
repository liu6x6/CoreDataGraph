# 渲染管线

## 坐标系统

- **世界坐标**：节点 `position`（卡片中心）、`size`（NodeMetrics 计算）
- **屏幕坐标**：`screen = world * zoom + pan`（`vm.toScreen/toWorld`）
- Canvas 内不手动变换点，而是变换上下文：
  ```swift
  ctx.translateBy(x: pan.width, y: pan.height)
  ctx.scaleBy(x: zoom, y: zoom)   // 之后全部按世界坐标绘制
  ```
- 卡片层：`.scaleEffect(zoom).position(vm.toScreen(pos))` —— 与 Canvas 同缩放，保证任意 zoom 下相对间距不变、不重叠
- 画布 `.clipShape(Rectangle())` 防止卡片溢出到侧栏

## GraphDrawing.draw 流程（Views/GraphDrawing.swift）

1. **inverse 去重**：`id = "fromEntity.name"`；若存在 twin（`toEntity.inverseName`）且本 id 字典序更大 → 跳过
2. **高亮/变淡判定**：selectedEntity 邻居、groupSelection、search 三层规则（`dimmed()` 闭包）
3. **路由**：`route(edge:from:to:collapsed:transform:) -> Route{points, toRight}`
   - 端口 = 关系行 Y（`NodeMetrics.relRowOffset`）× 卡片左右边缘（按 dx 符号选边）
   - Z 形正交：`[start, (midX, sy), (midX, ey), end]`；同行则直线
   - 圆角由 `roundedPolyline(radius: 7)` 用 quadCurve 实现
4. **箭头**（`drawArrowHead`，样式 `ArrowStyle`）：
   | 样式 | to-one | to-many |
   |---|---|---|
   | hollow | 空心三角(11pt) | +后退10pt第二空心三角 |
   | filled | 实心三角 | 双实心 |
   | lineChevron | 开放折线 `>` | 双折线 `⇒` |
   | crowFoot | 单横杠 tick | 三叉鸦爪 |
   | none | 无 | 无 |
   - **两端独立**：目标端=本关系基数；源端=twin(inverse)基数
5. **标签避让**：偏移 = `arrowExtent(isToMany:style) + 20`（源端用 twin 基数、目标端用本关系基数），Y 上移 10；白底芯片 `drawText`
6. **继承线**（`inheritance:` 参数）：child→parent 直线 + parent 端 16pt **空心三角**（`drawOpenTriangle`，半角 0.30）；与关系线独立绘制/高亮
7. **自引用**：卡片右上角小圆环 + 箭头 + 侧边标签

## 尺寸中枢 NodeMetrics（Model/GraphModel.swift）

- `scale`（字体比例，AppSettings.cardFontScale 注入）、`baseWidth`（AppSettings.cardWidth 注入，下限150）
- `width/headerHeight/rowHeight/sectionPad/bottomPad/moreRowHeight` 均为计算属性（×scale 或 =baseWidth）
- `size(for:collapsed:extraRelRows:)`：卡片高度 = 头 + 属性区(+more行) + 分隔1 + 关系区(+删除行+more行) + 底
- `relRowOffset(in:relName:collapsed:)`：关系行中心相对卡片中心的 Y（连线锚点；折叠时隐藏行锚到 "+N" 行）
- **改任何尺寸必须只改这里**——布局/绘制/SVG/命中全部依赖

## 颜色来源

- 线默认 `secondaryLabelColor`；高亮 = `AppSettings.selectedEdgeColor`；变淡 = 15% 透明
- 卡片选中边框/标题栏渐变 = `AppSettings.selectedNodeColor`
- Diff：added #34A853 绿 / removed #D93025 红 / changed #F29900 橙（画布与 SVG 一致）
- deletion rule 图标色：Cascade 红 / Nullify 蓝 / Deny 橙

## 观察与重绘

- Canvas 闭包内读取的 vm/settings 值**必须在 body 求值层先取局部变量**（GeometryReader 内 `let zoom/pan/lw/arrow/...`），否则设置变更不触发重绘
- 设置变更链路：AppSettings.didSet → postChanged → GraphCanvasView.onReceive → `applyMetrics() + vm.refreshNodeSizes()`（重算尺寸+resolveOverlaps）
