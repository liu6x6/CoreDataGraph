# 交互模型

## 手势矩阵（GraphCanvasView）

| 输入 | 行为 | 实现 |
|---|---|---|
| 空白拖动 | **框选**（marquee）| 单一 DragGesture，onChanged 首帧按 `NSEvent.modifierFlags` 分流 marquee/pan |
| ⌥+空白拖动 | 平移画布 | 同上分流 .pan |
| 双指滚动 | 平移（方向设置可反）| `NSEvent.addLocalMonitorForEvents(.scrollWheel)` + `.onContinuousHover` 门控（仅画布内消费，返回 nil）|
| 捏合 | 缩放（锚画布中心）| MagnificationGesture，保持中心世界点不变 |
| 空白单击 | 清除选择+组 | `vm.backgroundTapped()` |
| 卡片单击 | 选择/组逻辑 | `vm.cardTapped`：Shift=切换组成员；组内单击=仅移 Inspector 焦点不解散组；否则清组单选 |
| 卡片双击 | 展开/折叠 | `vm.toggleExpanded`（collapsedEntities 集合）|
| 卡片拖动 | 移动；**组内拖动整组移动** | dragOriginals + dragGroupOriginals 快照；首帧 `captureForUndo()`；onEnded `savePositions()` |
| 卡片右键 | 折叠/固定/复制/高亮关联 | contextMenu |
| 侧栏实体单击 | 选中+高亮邻居 | List selection + onTapGesture(count:1) |
| 侧栏实体双击 | **fly-to** | `vm.focusOn`：32步×16ms smoothstep 补间 pan+zoom（zoom<1 抬到 1.0，cap 2.0）|
| ⌘0 / ⇧⌘L | 适配 / 重布局 | Notification → Canvas onReceive |
| ⌘Z / ⇧⌘Z | 撤销/重做位置 | 菜单命令 + 工具栏按钮 → vm.undo/redo |
| ⌘, | 设置 | Settings scene |
| ⌥⌘1 / ⌘2 | 左栏/右栏开关 | 通知 → ContentView |

## 选择状态（vm）

- `selectedEntity: String?` — 单选：高亮邻居、其余变淡、Inspector 详情
- `groupSelection: Set<String>` — 框选/Shift 点选：整组拖动；>1 时非组变淡
- `marqueeRect: CGRect?`（屏幕坐标）— 拖动中覆盖层；`endMarquee()` 转世界坐标与卡片矩形相交测试
- 三态优先级（isNodeDimmed）：search 不匹配 > 组外 > 非邻居

## 撤销/重做

- vm 内 `undoStack/redoStack: [[String: CGPoint]]`（≤60）
- 捕获点：拖动首帧、setLayoutMode、relayout 通知
- `undo()/redo()`：弹栈→互推→applySnapshot（恢复坐标+savePositions+status）
- 菜单 `CommandGroup(replacing:.undoRedo)` 与工具栏按钮均经 `OpenRouter.shared.activeViewModel`

## 多窗口

- WindowGroup 每窗独立 vm；`OpenRouter.activeViewModel`（weak）= 最后 appear 的窗口
- AppleEvent/Dock/菜单打开 → activeViewModel，无窗口则 pendingURL 由首窗 `.task` 消费
