# BlackScreen

macOS 26 菜单栏一键黑屏小工具。左键点一下菜单栏图标，所有显示器立刻变成纯黑，按 `ESC` 退出。

## 功能

- 左键点击菜单栏图标：立即全屏纯黑，覆盖所有显示器、菜单栏和 Dock
- 黑屏时隐藏鼠标指针，退出后恢复
- 按 `ESC` 退出；`Cmd+Q` 也可以退出（防卡死）
- 黑屏期间其他 App 抢走焦点时会自动抢回，避免 `ESC` 因此失效
- 授予辅助功能权限后，即使焦点被其他 App 抢走，`ESC` 也能全局退出（可选）
- 右键点击图标：弹出菜单，可「立即黑屏」「启用可靠 ESC（辅助功能）…」或「退出 BlackScreen」
- 黑屏期间鼠标点击由覆盖层接收，不会误触下方应用
- 无 Dock 图标，无第三方依赖，退出黑屏后自动把焦点还给原来的应用

## 构建与运行

```bash
./build.sh
open build/BlackScreen.app
```

构建产物在 `build/BlackScreen.app`，可以直接拖进 `/Applications`。当前构建目标为 macOS 26（`swiftc` 默认使用本机 SDK）。

## macOS 26 菜单栏说明

macOS 26 Tahoe 默认把第三方状态项排在菜单栏左侧，Chrome 这类菜单较宽的应用激活时可能把图标遮住。

BlackScreen 首次运行会写入一个靠右的默认位置：

```
NSStatusItem Preferred Position Item-0 = 1400
```

让图标落在右侧统计区，避免被应用菜单遮挡。之后 App 不会覆盖已有位置，手动调整会保留。

如果图标仍然看不到，检查：

1. 打开「系统设置 → 菜单栏 → 允许在菜单栏显示」，确认 BlackScreen 的开关是开启的
2. 切换到菜单较短的应用（如 Finder）看看图标是否出现

## 可靠 ESC（可选）

默认靠本地键盘监听退出，并在焦点被抢时主动抢回。要覆盖极端场景（系统弹窗或其他 App 持续抢焦点），可以授予辅助功能权限，让 BlackScreen 在黑屏期间额外监听全局 `ESC`：

1. 右键点击菜单栏图标
2. 选择「启用可靠 ESC（辅助功能）…」
3. 在「系统设置 → 隐私与安全性 → 辅助功能」中打开 BlackScreen

如果右键菜单里没有入口，也可以直接触发授权提示：

```bash
open build/BlackScreen.app --args --request-accessibility
```

该权限只在黑屏显示期间用于监听 `ESC`，退出黑屏后会移除全局监听。

授权成功后，右键菜单会显示「可靠 ESC 已启用（辅助功能）」。

如果重新构建过 App，ad-hoc 签名会变化，辅助功能里的旧开关可能失效；把 BlackScreen 的开关关掉再打开一次即可。

## 原理

- `NSStatusItem` 驻留菜单栏
- 每块屏幕创建一个 `.screenSaver` 层级的无边框 `NSWindow`，背景纯黑
- 本地键盘事件监听捕获 `ESC` 和 `Cmd+Q`
- 右键菜单通过本地 `rightMouseUp` 监听触发（`NSStatusBarButton` 不派发右键 action）
- 监听 `NSApplication.didResignActiveNotification`，焦点被抢时立即激活回本 App
- 授予辅助功能权限时，黑屏期间额外注册全局 `ESC` 监听
- `NSCursor.hide()` / `NSCursor.unhide()` 隐藏和恢复鼠标指针

## 已知限制

- 多显示器按 `NSScreen.screens` 逐屏创建窗口，但当前只在单屏环境实测
- 未授予辅助功能权限时，极端焦点抢占或安全对话框可能让 `ESC` 失效；授予后由全局监听兜底，仍可用 `Cmd+Option+Esc` 强制退出 BlackScreen
