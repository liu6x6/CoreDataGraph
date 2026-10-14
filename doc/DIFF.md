# 版本 Diff

## 入口

工具栏 Compare 按钮 → `ComparePanel` popover：**旧/新两个版本 Picker**（任意组合）→ `vm.setCompare(old:new:)`。关闭 = `clearCompare()`。切换当前版本（侧栏 Picker）会清除 diff。

## 计算（Model/ModelDiffer.swift）

`diff(old:new:) → ModelDiff{addedEntities, removedEntities, changedEntities[EntityChange]}`
- EntityChange 含属性/关系各自的 added/removed/changed 列表，changed 带人类可读 detail（类型/optional/默认值/transformer/目标/删除规则/inverse/toMany 变化）
- `vm.buildDiffLookups()` 拍平为行级查询表：
  - `diffAttrStatus[entity][attr] -> DiffStatus`
  - `diffRelStatus[entity][rel] -> DiffStatus`

## 图构建（vm.rebuildGraph diff 分支）

- **显示 NEW 版本文档**，实体按 `ModelDiffer.entityStatus` 着色（added/changed）
- **幽灵卡片**：old 有 new 无 → 追加 `.removed` 实体
- **边**：
  - 存活实体的关系边：status 取 `diffRelStatus`（added 绿/changed 橙）
  - 幽灵实体的关系边：全部 `.removed`（红）→ 删除实体不再孤立
  - 存活实体**被删除的关系**：从 oldDoc 找回 RelationshipInfo 补 `.removed` 幽灵边
- 卡片行级：属性行绿点/橙点+着色；**被删关系显示红色删除线行**（`removedRelationshipNames`，卡片高度经 `extraRelRows` 计入）

## 展示

- 画布：边/卡片 diff 色（见 RENDERING.md 颜色表）
- 侧栏：diff 摘要区（+/−/~ 行，点击 fly-to）
- Inspector：`DiffInspector` 完整变更清单

## 验证方法

离线 harness：解析两个版本 contents → ModelDiffer.diff → 打印 summary（见 AI_DEV_GUIDE 示例；v20→v27 = "+2 实体, ~5 实体"）。
