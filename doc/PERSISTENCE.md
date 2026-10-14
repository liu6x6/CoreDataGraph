# 持久化与系统集成

## UserDefaults 键清单

| 键 | 内容 | 写入方 |
|---|---|---|
| `settings.cardFontScale` | 字体比例 0.8–1.6 | AppSettings |
| `settings.cardWidth` | 卡宽 150–400（clamp≥150）| AppSettings |
| `settings.edgeLineWidth` | 线宽 0.5–4 | AppSettings |
| `settings.arrowStyle` | ArrowStyle.rawValue | AppSettings |
| `settings.showAttributeTypes` / `settings.showEdgeLabels` / `settings.scrollPanReversed` | Bool | AppSettings |
| `settings.selectedNodeColor` / `settings.selectedEdgeColor` | hex `#RRGGBB` | AppSettings |
| `customLayoutPositions.v1` | `[模型path#版本名: [entity: [x,y]]]` | PositionStore |
| `recentModelBookmarks`(+`.bookmarks`) | 最近文件元数据+bookmark Data | RecentFilesStore |
| `lastOpenedBookmarkID` | 启动自动恢复用 | RecentFilesStore |
| `showSidebar` / `showInspector` | 面板开关 | ContentView @AppStorage |

## 排版记忆（PositionStore）

- key = `rootURL.path + "#" + version`；拖动 onEnded / undo 恢复时 `vm.savePositions()` 写入并置 layoutMode=.custom
- 打开模型 `applyLayout(initial:)` 最先尝试恢复；显式 setLayoutMode 清除
- 模型新增实体：停右侧网格 + `resolveOverlaps`

## 最近文件（RecentFilesStore）

- **security-scoped bookmark**（`.withSecurityScope`）持久化；resolve 时处理 stale 刷新
- `markLastOpened` 记录最后打开项 → 启动 `vm.restoreLastDocument()`
- 消费端：欢迎页列表、File→Open Recent 子菜单、Dock 菜单（`applicationDockMenu`）

## 文件监听（自动刷新）

- `DirectoryWatcher`：`open(O_EVTONLY)` + DispatchSource(.write/.delete/.rename/.extend/.attrib)
- 监听 rootURL + 所有版本目录；事件 debounce 600ms → `reloadPreservingLayout()`（保留用户坐标后重建）
- 沙盒下依赖 open() 时 `startAccessingSecurityScopedResource()` 持有的 scope

## Finder / LaunchServices 集成

- `SupportingFiles/Info.plist`：
  - `CFBundleDocumentTypes`：LSItemContentTypes（**自有前缀** `com.selflearn.coredatagraph.*`）+ **CFBundleTypeExtensions 兜底**（xcdatamodeld/xcdatamodel/mom/momd）
  - `UTImportedTypeDeclarations`：四个类型（modelbundle/model  conforms public.directory；compiledmodel conforms public.data）
- 事件链：`AppDelegate.application(_:open:)` → `OpenRouter.requestOpen` → 活动窗口 vm / pendingURL
- 陷阱：UTI 用 `com.apple.*` 前缀会被忽略；改 plist 后需 `lsregister -f <app>` 或重启 Finder/注销刷新缓存
- 注意：`mom` 有 Apple 官方 UTI（com.apple.xcode.mom），xcdatamodeld 没有（探测为 dyn.*），故扩展名兜底必需

## 沙盒

- App Sandbox ON；`ENABLE_USER_SELECTED_FILES = readwrite`（NSSavePanel 硬性要求，readonly 会 crash ViewBridge）
