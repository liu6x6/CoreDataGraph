# CHANGELOG

## v1.0（2026-10-14，本仓库当前状态）

### 核心
- 通用模型加载：xcdatamodeld（多版本+切换）/ xcdatamodel / contents / mom / momd
- Xcode 风格关系图：正交圆角连线、行级锚点、inverse 合并单线、两端基数箭头、关系名/inverse 名两端标签
- 布局：自定义记忆 / XML 原始排版 / 力导向（层级种子+矩形碰撞，0 重叠）/ 层级（层内换行）
- 交互：框选成组整组拖动、Shift 点选、fly-to 聚焦、双指滚动平移（方向可设）、⌥平移、捏合缩放、⌘0、⇧⌘L、整图等比缩放
- 版本 Diff：任意两版本、幽灵卡片+幽灵边、卡片行级着色（绿点/橙点/红色删除线行）、Inspector 明细
- 撤销/重做：⌘Z/⌘Z + 工具栏按钮（位置快照栈）
- 导出：PNG(2x) / SVG(纯矢量) / Mermaid / DOT
- 设置(⌘,)：字体比例、卡宽(≥150)、线宽、箭头四样式+无、标签显隐、类型显隐、选中双色、滚动方向
- 集成：Finder 打开方式/双击/open -a（文档类型注册）、Dock 菜单与 File→Open Recent 子菜单、启动恢复上次模型、Xcode 保存自动刷新（保留手动布局）
- App 图标全套尺寸

### 关键修复史
- 文件面板选不中 xcdatamodeld（package 非 folder → allowedContentTypes [.item]）
- NavigationSplitView 列协商错乱 → 自管理三栏 HStack
- 缩放时卡片不缩放导致互叠 → ctx.scaleBy + scaleEffect 整等比
- 卡片溢出盖侧栏 → clipShape
- NSSavePanel crash → ENABLE_USER_SELECTED_FILES readwrite
- BFS 分层环死循环 → visited 判定
- 标签压箭头 → arrowExtent 动态避让
- UTI com.apple.* 前缀无效 → 自有前缀 + CFBundleTypeExtensions + lsregister

## Roadmap（未做）
- 大模型性能（Barnes-Hut / minimap / 卡片全 Canvas 化）
- 布局 JSON 导入导出（团队共享）
- 单元测试 target
- 本地化 en
- 搜索命中行高亮、配置(configuration)分色、打印
