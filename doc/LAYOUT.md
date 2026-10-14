# 布局算法（ViewModel/LayoutEngine.swift）

## 模式与优先级

`LayoutMode`: `.custom(自定义记忆) / .saved(原始排版) / .force(力导向) / .hierarchical(层级)`

`vm.applyLayout(initial:)` 优先级：
1. **PositionStore 记忆**（initial 或 mode==.custom 时）：按名恢复坐标并 pin；缺失的新实体停放到右侧网格 + resolveOverlaps
2. initial 自动选择：模型含 `<elements>` 坐标 → .saved，否则 → .force
3. 显式模式执行对应算法

`vm.setLayoutMode(_:)`：显式切换会**清除该版本的排版记忆**（表示"重新排"），之后拖动卡片重新记忆。

## forceDirected（默认）

三阶段：
1. **层级种子**：先跑 hierarchical 得到初始位置（相关实体同区域），避免随机起点
2. **力模拟**（迭代数 = clamp(20000/n+100, 140, 420)）：
   - 弹簧：有边节点对，rest=430，k=0.3
   - 温和斥力：d<1400 时 `min(110000/d², 16)`
   - **矩形分离**：两卡包围盒（含 gapX=80/gapY=70 间隙）相交时沿最小穿透轴推离（×0.55，cap 70）
   - 弱向心力 0.0018（防挤中心也防飞散）
   - 积分限幅 maxStep 26 → ×0.985 冷却至 0.8
3. **resolveOverlaps**：≤60 轮确定性扫除，数学保证 0 重叠

验证基准：Cookidoo 21 节点 span≈2988×1416、0 重叠；合成 80 节点 span≈3869×2607、0 重叠、<10ms。

## hierarchical

1. BFS 分层（**visited 判定，防环死循环**——历史 bug：relaxation 版在 A→B→A 环上无限循环）
2. 根 = 无 parentEntity 且入度 0；无则出度最大者
3. 层内**重心排序**（按父层槽位均值）
4. **层内换行**：每行 ≤ `max(3, 2600/xGap)` 张（xGap = 卡宽+120）；折行保持重心顺序 → 关系近的上下相邻
5. 垂直间距：行内 160 / 层间 240；每行独立水平居中；整体垂直居中

## applySaved

读 `EntityNode.savedPosition`（XML `<elements>` 的 positionX/Y+width/height 中心）；无坐标的实体停右侧 3×N 网格。

## 调参入口

全部为 LayoutEngine 内局部常量（gapX/gapY/rest/重力/行宽上限）。改间距后请跑 `/tmp` 风格离线 harness 验证 span 与 overlaps（见 AI_DEV_GUIDE）。
