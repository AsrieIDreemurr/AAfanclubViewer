# AA Fanclub Viewer

`http://aafanclub.com/` 的 Windows 与 Android 原生阅读器。应用不嵌入 WebView 或其他浏览器内核，而是直接读取站点 HTML，再用 Flutter 控件按照原站样式渲染。使用CodeX，这个README也是AI写的，之后再修改。

## 阅读

- 启动后直接打开 AA同好会揭示板
- 首页帖子预览、帖子一览和帖子分页的专用解析
- 原站 `Saitamaar` 字体、16px 字号和 1.0 行高
- `#EFEFEF` 页面底色、`#CCFFCC` 首页信息表、蓝色链接、绿色贴主、红色骰子结果
- AA 空格、换行以及不折行的横向滚动
- 首页公告栏按原站表格还原：一圈外框加每格一条细线，边框按屏幕像素密度绘制成一物理像素
- 链接按下时变为原站的 `alink` 红色；帖子标题与导航格的可点范围延伸到整格，不只是字身
- 无地址栏或 HTTP 安全提示，阅读内容占满应用窗口
- 底部滑条在 30%～160% 间调节整体文字/AA 显示比例

## 操作方式

手机保持无按钮的沉浸阅读，电脑给出可见控件：

- **（重要）左右两侧中心是不显示图标的扩大热区**：轻点左侧刷新、轻点右侧滑出阅读工具；滑动不会误触发
- 在阅读区**双击**可让两个热区以半透明灰块显形，显形期间可拖动位置、拖内侧手柄调整大小，改动过的一侧旁会出现恢复默认按钮；任意点击、滚动或跳转都会重新隐藏
- 长按仍归文字选择，双击不会被选词抢走
- 热区尺寸与位置按左右两侧分别持久化，存的是相对屏幕的比例，换屏幕或转屏后默认值重新计算
- Android 系统返回键依次收起面板、后退历史，再按一次才退出应用
- Windows 显示经典样式工具条（后退／前进／刷新／首页／帖子一览／翻页／跳楼层／阅读工具），并支持快捷键：`F5`、`Alt+←`、`Alt+→`、`Alt+Home`、`Ctrl+PageUp`、`Ctrl+PageDown`、`Ctrl+G`、`Ctrl+D`、`Esc`；输入文字时快捷键自动让路

## 刷新与定位

- 手动刷新，不进行自动轮询
- 帖子一览刷新时重新读取完整列表，允许帖子顺序变化
- 帖子阅读页刷新时保留已显示楼层，只追加新的楼号
- 当最后一页在刷新期间产生新分页时，继续读取新页并追加
- 阅读进度按楼层实时记录，向前向后都跟随当前位置，再次进入时跳到对应分页和楼层
- 帖子标签可从侧栏逐个关闭，关闭后该帖的楼层书签仍然保留
- 楼层书签的添加、跨分页精确跳转与删除；书签较多时在面板上方独立滚动
- 侧栏与桌面工具条均可上一页／下一页，并可输入楼层号跨分页跳转
- 「只看贴主」与「查看全部」按站点当前页面的实际文字与链接显示，只看贴主视图的分页同样可用
- 访问过的帖子分页缓存到应用私有目录，再次访问无需联网；手动刷新强制更新，侧栏可清除缓存

## 发帖

- 登录设置、回复和新建帖子表单；登录会话 Cookie 在本次运行期间持续使用
- 表单提交前把换行统一成 CRLF，与浏览器提交 textarea 的行为一致——站点按 CRLF 切分正文来插入 `<br>` 并判断首页预览是否折叠，只发 LF 会让整篇被当作一行而永不折叠
- 发帖器为图层式画布：可嵌入多个文字窗口与 AA，双指缩放、拖动平移
- 画布左侧与上方是画外区，用灰色斜线标出；打开时视图停在正文起点，拖进画外区的文字在合成时被丢弃，框内文字位置不受影响
- 合成排版按**实测像素**推进而非按字符格数：`Saitamaar` 是比例字体，全角空格是 2.2 个空格宽、`A` 是 2.0、`i` 只有 0.6，按格数计算会让长段空格逐字累积偏移
- 点「确认」后预览可直接编辑文字，「取消」丢弃这些修改且不会变回窗口

## AA 素材选择器

- 素材来自 `aa.yaruyomi.com` 的公开目录
- 每次打开自动回到上次浏览的文件
- 可收藏单个 AA、整个文件，以及**文件夹**
- 位置栏是可点击的路径，每一级文件夹都能跳回；即使文件是从搜索、历史或收藏直接打开的，路径也从文件自身的目录反查目录树得到

## 其他

- HTTP 超时、重定向和 8 MB 单页大小限制
- 站点没有 SSL，Android 已允许访问其明文 HTTP。应用界面不显示地址栏或"不安全"提示

## 代码结构

```text
lib/
├─ application/  导航、刷新、书签、阅读进度与热区布局状态
├─ data/         HTTP 会话、帖子缓存、字符集、专用解析器与增量合并
├─ domain/       页面、帖子、分页、富文本和帖子摘要模型
└─ ui/           原站风格的 Flutter 原生界面
```

重要入口：

- `lib/data/aafanclub_adapter.dart`：首页、列表和帖子 HTML 解析
- `lib/data/forum_repository.dart`：刷新合并及登录、回复、新帖请求
- `lib/data/page_source.dart`：HTTP 会话、Cookie 与表单提交的换行规范化
- `lib/data/thread_page_cache.dart`：Windows/Android 应用私有目录中的帖子分页缓存
- `lib/application/reader_store.dart`：显示比例、阅读进度、楼层书签与热区布局持久化
- `lib/ui/viewer_page.dart`：原站风格阅读页、热区编辑、桌面工具条与自动楼层定位
- `lib/ui/reader_side_panel.dart`：右侧滑出工具面板及表单
- `lib/ui/post_composer_sheet.dart`：图层式发帖画布与按像素对齐的文本合成
- `lib/ui/aa_picker_page.dart`：AA 素材浏览、搜索与收藏
- `tool/live_smoke.dart`：只读在线冒烟检查

## 验证

```powershell
flutter analyze
flutter test
flutter build apk --release
flutter build windows --release
```

自动化测试中的表单请求只发送给 `MockClient`，不会向线上网站登录、回帖或发帖。测试里的昵称与密钥都是占位值。

`tool/live_smoke.dart` 需要 Flutter 运行环境，不能用 `dart run` 直接执行。

Android APK 输出到 `build/app/outputs/flutter-apk/`，Windows 产物在 `build/windows/x64/runner/Release/`（`.exe` 需与同目录的 `flutter_windows.dll` 和 `data/` 一起分发）。两者都会被复制到 `dist/`，该目录不进仓库。

Windows 编译需要 Visual Studio 的"使用 C++ 的桌面开发"工作负载。**只用到它的 C++ 工具链，不需要把 Visual Studio 当编辑器。** 若 Flutter 版本早于 3.47，它不认识 Visual Studio 2026（版本号 18），会退回到不存在的 "Visual Studio 16 2019" 生成器而失败；对应的修复是在 `flutter_tools` 的 `visual_studio.dart` 中补上 `18 => 'Visual Studio 18 2026'`，改完需删除 `bin/cache/flutter_tools.stamp` 与 `flutter_tools.snapshot` 让快照重建。

## 字体

`assets/fonts/Saitamaar.ttf` 是站点当前提供的字体副本，随应用打包以保证 Windows 与 Android 的 AA 字宽一致。来源与许可说明见 `assets/fonts/NOTICE.txt`。
