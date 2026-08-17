# AA Fanclub Viewer

`http://aafanclub.com/` 的 Windows 与 Android 原生阅读器。应用不嵌入 WebView 或其他浏览器内核，而是直接读取站点 HTML，再用 Flutter 控件按照原站样式渲染。使用CodeX，这个README也是AI写的，之后再修改。

## 已实现

- 启动后直接打开 AA同好会揭示板
- 首页帖子预览、帖子一览和帖子分页的专用解析
- 原站 `Saitamaar` 字体、16px 字号和 1.0 行高
- `#EFEFEF` 页面底色、`#CCFFCC` 首页信息表、蓝色链接、绿色贴主、红色骰子结果
- AA 空格、换行以及不折行的横向滚动
- 无地址栏或 HTTP 安全提示，阅读内容占满应用窗口
- 手动刷新，不进行自动轮询
- 帖子一览刷新时重新读取完整列表，允许帖子顺序变化
- 帖子阅读页刷新时保留已显示楼层，只追加新的楼号
- 当最后一页在刷新期间产生新分页时，继续读取新页并追加
- 底部滑条在 30%～160% 间调节整体文字/AA 显示比例
- 自动按楼层持久化每个帖子的最远阅读进度，再次进入时跳到对应分页和楼层
- 楼层书签的添加、跨分页精确跳转与删除；书签较多时在面板上方独立滚动
- 访问过的帖子分页缓存到应用私有目录，再次访问无需联网；手动刷新强制更新，侧栏可清除缓存
- 首页公告移除空白段落，且不重复显示“点此发帖”和昵称旁“修改”入口
- 登录设置、回复和新建帖子表单；登录会话 Cookie 在本次运行期间持续使用
- HTTP 超时、重定向和 8 MB 单页大小限制

- （重要）左右两侧中心使用不显示图标的扩大热区：轻点左侧刷新、轻点右侧滑出阅读工具；滑动不会误触发

站点没有 SSL，Android 已允许访问其明文 HTTP。应用界面不显示地址栏或“不安全”提示。

## 代码结构

```text
lib/
├─ application/  导航、刷新、书签与阅读进度状态
├─ data/         HTTP 会话、帖子缓存、字符集、专用解析器与增量合并
├─ domain/       页面、帖子、分页、富文本和帖子摘要模型
└─ ui/           原站风格的 Flutter 原生界面
```

重要入口：

- `lib/data/aafanclub_adapter.dart`：首页、列表和帖子 HTML 解析
- `lib/data/forum_repository.dart`：刷新合并及登录、回复、新帖请求
- `lib/data/thread_page_cache.dart`：Windows/Android 应用私有目录中的帖子分页缓存
- `lib/application/reader_store.dart`：显示比例、阅读进度与楼层书签持久化
- `lib/ui/viewer_page.dart`：原站风格阅读页、边缘触发与自动楼层定位
- `lib/ui/reader_side_panel.dart`：右侧滑出工具面板及表单
- `tool/live_smoke.dart`：只读在线冒烟检查

## 验证

```powershell
flutter analyze
flutter test
dart run tool/live_smoke.dart
flutter build apk --debug
```

自动化测试中的表单请求只发送给 `MockClient`，不会向线上网站登录、回帖或发帖。

Android 调试 APK 输出到 `build/app/outputs/flutter-apk/app-debug.apk`。Windows 编译需要安装 Visual Studio 的“使用 C++ 的桌面开发”工作负载。

## 字体

`assets/fonts/Saitamaar.ttf` 是站点当前提供的字体副本，随应用打包以保证 Windows 与 Android 的 AA 字宽一致。来源与许可说明见 `assets/fonts/NOTICE.txt`。
