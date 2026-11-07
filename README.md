# KML Explorer

> 一个用来**管理与查看 KML 轨迹文件**的 Flutter 跨平台应用：多地图供应商在线底图、轨迹解析与渲染、轨迹样式/区间编辑、图片标注点浏览、实时定位、以及 WebDAV 云同步。

- **包名 / 应用名**：`kml_explorer`（v1.0.0）
- **技术栈**：Flutter 3.32.4 + Dart 3.8.1（`sdk: ^3.8.1`）
- **代码规模**：`lib/` 下 21 个 Dart 文件，约 6700 行（重构前 14 个文件约 7000 行）
- **目标平台**：Android / iOS / Windows / macOS / Linux / Web（实际以 Android + Windows 为主）
- **构建状态**：✅ `flutter analyze` 零问题 · ✅ 12 个单元测试通过 · ✅ Android release APK 已产出并验签

---

## 0. 交付物（本次优化）

| 项 | 位置 |
| --- | --- |
| Android release APK（53.6 MB，v2 签名） | 本地构建产物（体积原因不入库，请自行构建或从 Releases 下载） |
| 原始构建输出 | `build/app/outputs/flutter-apk/app-release.apk` |
| 一键构建脚本 | [scripts/build_android.ps1](scripts/build_android.ps1) |
| 一键环境检测 | [scripts/setup_env.ps1](scripts/setup_env.ps1) |
| 签名生成脚本 | [scripts/setup_signing.ps1](scripts/setup_signing.ps1) |

**APK 信息**：`com.example.kml_explorer` v1.0.0 (versionCode 1) · minSdk 24 · targetSdk 35 · 含 `arm64-v8a / armeabi-v7a / x86 / x86_64` 四个 ABI · 签名证书 `CN=KML Explorer`（SHA-256 `296f26da…aaaf21`）。

构建并用脚本产出 APK：

```powershell
pwsh -File scripts/build_android.ps1
```

安装到手机：

```powershell
# 手机开启 USB 调试后
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

---

## 1. 这个项目是干什么的

用户从「两步路（2bulu）」等户外 App 导出 KML 轨迹文件，本应用负责：

1. 导入 KML（或从 WebDAV 拉取），解析出**轨迹点**与**标注点**；
2. 在可切换底图的地图上用彩色折线 + 圆形标记渲染出来；
3. 给每条轨迹单独设置**显示名 / 颜色 / 线宽 / 起止点区间**；
4. 用折线图看**海拔 / 速度 / 里程**曲线，配合区间滑块裁剪要显示的那一段；
5. 自动把导入的文件上传到 WebDAV，实现多设备间同步。

---

## 2. 快速开始

### 2.1 最省事：用脚本

```powershell
# 检测环境 + 拉依赖 + 分析 + 测试（不构建）
powershell -ExecutionPolicy Bypass -File scripts\setup_env.ps1

# 检测环境 + 直接构建 release APK
powershell -ExecutionPolicy Bypass -File scripts\build_android.ps1
```

脚本会自动定位 Flutter / JDK 17 / Android SDK，设好 `FLUTTER_STORAGE_BASE_URL`，并写对 `local.properties`。

### 2.2 手动命令

```bash
cd kml_explorer
flutter pub get
flutter analyze
flutter test

# 调试运行
flutter run -d windows
flutter run -d <android-device>

# 打包
flutter build apk --release
flutter build apk --release --split-per-abi   # 按 ABI 拆分，单包更小
flutter build appbundle --release             # 上架 Google Play 用
```

### 2.3 本机环境（已实测可用）

| 组件 | 路径 | 版本 |
| --- | --- | --- |
| Flutter | `D:\ProgramData\flutter` | 3.32.4 stable（Dart 3.8.1） |
| JDK | `C:\Users\lakes\.jdks\tmp17\jdk-17.0.2` | OpenJDK 17.0.2 |
| Android SDK | `C:\Users\lakes\AppData\Local\Android\Sdk` | build-tools 35 / platforms 35 |

### ⚠️ 本机构建的三个坑（必读）

这次踩了很久，都是**环境**问题而非代码问题，记下来免得重复踩：

1. **Flutter 引擎产物下载被重置**
   `io.flutter:*_release` 这些 jar 来自 `storage.googleapis.com`，直连会 `Connection reset`，表现为构建长时间"假死"。
   必须在构建前设环境变量：

   ```powershell
   $env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
   $env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
   ```

2. **全局 `~/.gradle/init.gradle` 与 Flutter 插件冲突**
   原文件用 `allprojects { repositories { maven {...} } }` 注入阿里云镜像，而 Flutter 自带的
   `flutter_tools/gradle/settings.gradle.kts` 声明了 `FAIL_ON_PROJECT_REPOS`，两者直接冲突，报错还极具迷惑性：

   > Build was configured to prefer settings repositories over project repositories
   > but repository 'maven' was added by settings file 'settings.gradle.kts'
   > （文案说的是 settings，实际指的是 **project** 级仓库）

   已改为只在 `settingsEvaluated` 里注入 `pluginManagement.repositories`，原文件备份为
   `~/.gradle/init.gradle.bak-20261107`。**换机器如果也配了类似的全局镜像，注意同一个坑。**

3. **JDK 必须是完整 JDK，不是 JRE**
   `C:\Program Files\Eclipse Adoptium\jre-17...` 没有 `javac`，`~/.jdks/jdk-17.0.2` 缺 `lib/jvm.cfg`，
   两者都会失败。脚本按"有 `bin\javac.exe` 且有 `lib\jvm.cfg`"两个条件筛选。

### 2.4 首次运行注意

- 桌面端左侧会并排显示文件管理面板（固定宽 320），移动端只显示地图；可用 AppBar 最右侧按钮收起/展开。
- 启动时会先探测网络、再逐个测试底图可用性，因此**前几秒地图可能还在加载**，属正常现象。
- 使用天地图底图需要自行申请 API Key（见第 5 节）。

---

## 3. 目录结构

```
kml_explorer/
├── lib/                        # 全部业务代码（约 5300 行）
│   ├── main.dart               # 应用入口（24 行，仅装配 MaterialApp）
│   ├── models/                 # 数据模型
│   │   ├── kml_file.dart       # 轨迹文件模型 + KmlFileManager（元数据 CRUD/备份）
│   │   ├── kml_parser.dart     # KML XML 解析器（TrackPoint 也定义在此）
│   │   ├── kml_marker.dart     # 标注点模型（图片/扩展数据）
│   │   ├── map_config.dart     # 天地图 API Key 的存取
│   │   └── tile_server.dart    # 底图供应商定义（含 isChineseMap 坐标系标记）
│   ├── controllers/
│   │   └── location_controller.dart  # 定位状态机（ChangeNotifier，含按平台的 LocationSettings）
│   ├── pages/                  # 界面
│   │   ├── map_page.dart               # 地图主页（约 820 行）
│   │   ├── file_manager_page.dart      # KML 文件列表、标签筛选、导入/删除/去重
│   │   ├── track_edit_dialog.dart      # 轨迹编辑（曲线图 + 区间滑块）★实际使用
│   │   ├── track_edit_page.dart        # 轨迹编辑整页版（含 Canvas 预览）☆未被引用
│   │   ├── marker_info_dialog.dart     # 标注点详情（在线图片 + 扩展数据）
│   │   ├── tile_server_dialogs.dart    # 底图选择/设置/天地图密钥三个对话框
│   │   ├── webdav_settings_page.dart   # WebDAV 服务器配置
│   │   └── webdav_file_picker_page.dart # WebDAV 远端文件多选下载
│   ├── services/
│   │   ├── webdav_service.dart  # WebDAV 单例：上传/下载/列目录/去重
│   │   ├── permission_service.dart # 定位权限申请（含 Android 13+ 精确位置）
│   │   ├── settings_service.dart   # SharedPreferences 键集中管理
│   │   ├── tile_probe.dart         # 底图健康探测 + 网络连通性检查
│   │   └── track_renderer.dart     # KML → Polyline/Marker 图层编译
│   └── utils/
│       └── coord_transform.dart # WGS-84 ⇄ GCJ-02 坐标转换
├── scripts/                    # 开发/构建脚本（见第 2 节）
│   ├── setup_env.ps1           # 环境检测 + pub get + analyze + test
│   ├── build_android.ps1       # 一键构建 APK（自动处理镜像与 JDK）
│   └── setup_signing.ps1       # 生成 release keystore 与 key.properties
├── android/                    # Android 工程（Gradle Kotlin DSL、签名、权限声明）
├── ios/  macos/  linux/  windows/  web/   # 各平台脚手架
├── reference/                  # 调试用素材
│   ├── 2025-06-0210_28东莞长安莲花山.kml
│   ├── 鲲鹏径一到十一段（合并）.kml
│   └── 07-147r2_OGC_KML_2.2.pdf       # OGC KML 2.2 规范
├── test/                       # 单元测试（12 个，全部通过）
│   ├── kml_parser_test.dart    # 解析器：gx:Track / LineString / 标签 / 颜色 / 容错
│   └── coord_transform_test.dart # 坐标转换：偏移方向、往返精度、批量转换
├── pubspec.yaml  pubspec.lock
└── analysis_options.yaml       # flutter_lints 默认规则
```

> 项目**没有 git 仓库**（无 `.git/`、无提交历史），因此无法回溯逐次改动。从 `.idea/`（2025-06-18 创建）与 `.vscode/` 并存可以看出它是在 IDE 里由 AI 编程助手迭代出来的，但目录里没有任何能指认 Trae 或 Claude Code 的元数据（无 `.trae/`、无 `CLAUDE.md`）。**代码风格线索**：全中文注释与 UI 文案、`debugPrint` 大量保留、注释里出现 `// 新增：`、`// 删除此行: geolocator: ^10.1.0`、`// 修复方法名引用错误` 这类"改动留痕"式注释，以及原本 `main.dart` 膨胀到 2102 行——这些都更像"边聊边改"的迭代产物，而不是先设计后编码。如果是想确认工具，只能按时间线去比对当时的编辑器记录。

### 时间线（按文件修改时间）

| 时间 | 内容 |
| --- | --- |
| 2025-06-18 20:20 | Flutter 工程脚手架生成（`.metadata`、`.gitignore`、`.idea`） |
| 2025-06-20 | 轨迹编辑页 → 天地图配置 → 坐标转换 → 标注点模型 → 解析器 |
| 2025-06-21 19:xx | 文件管理页、WebDAV 三个文件、`kml_file.dart`（主体功能收尾） |
| 2025-12-12 ~ 12-13 | 重写 README、调 `pubspec.yaml` 依赖、改 `main.dart` 与权限服务 |
| 2026-11-07 | 本次：修编译错误、拆 `main.dart`、补测试、配通 Android 构建、出 APK |

---

## 4. 架构与模块职责

分层仍然是 models / controllers / services / pages / utils 五层，无状态管理框架、无路由框架，但已经把原本塞在 `main.dart` 里的职责拆了出去：

```
                  ┌──────────────────────────────────────┐
                  │  main.dart → pages/map_page.dart     │
                  │  地图 / 底图 / 定位按钮 / 菜单 / 诊断  │
                  └──┬──────────┬──────────┬─────────────┘
                     │          │          │
        回调通知        │          │ 弹窗      │ 导航
                     ▼          ▼          ▼
        FileManagerPage   TrackEditDialog  WebDavSettingsPage
        (列表/筛选/可见性)  (曲线图/区间/样式)  WebDavFilePickerPage
                     │          │          │
                     └──────────┴──────────┘
                                │
                       KmlFileManager（元数据 JSON CRUD/备份）
                          │                     │
                KmlParser ┘                     └ WebDavService（单例）

  支撑组件（本次拆出）：
    TrackRenderer          KML → Polyline/Marker，统一处理 GCJ-02 转换
    LocationController     定位流 + 间隔设置（ChangeNotifier）
    TileServerProbe        底图健康探测 + 网络连通性
    SettingsService        SharedPreferences 键集中管理
    tile_server_dialogs    底图选择/设置/天地图密钥三对话框
```

### 4.1 `models/kml_file.dart` — 数据中枢（762 行）

`KmlFile`：一条轨迹的全部运行期状态 —— 文件路径、`List<TrackPoint>`、`List<KmlMarker>`、可见性、显示名、颜色、线宽、起止点索引、KML 里的 `trackName`/`trackTags`、以及 WebDAV 的 `isCloudSaved`。关键派生逻辑：

| 成员 | 作用 |
| --- | --- |
| `visiblePoints` | 按 `startPointIndex..endPointIndex` 切片，越界自动 clamp |
| `getVisiblePointsForMap(isChineseMap)` | 国内底图时整段转 GCJ-02，否则原样 WGS-84 |
| `getMarkersForMap(isChineseMap)` | 标注点同理转换 |
| `bounds` / `boundsWithPadding` | 轨迹包围盒（后者加 15% 边距） |
| `optimalZoom` | 按跨度反推缩放级：`log(地球周长 / (跨度×111320)) / log2`，夹在 3–18 |
| `copyWith` / `toJson` / `fromJson` | 不可变式修改与序列化（颜色存 `toARGB32`） |

`KmlFileManager`（全静态方法）负责**持久化**，策略相当谨慎：

- 元数据落在 `<应用文档目录>/kml_files_metadata.json`，KML 原文落在 `<应用文档目录>/kml_files/`
- 写入流程 = **先备份**（`_backup`）→ **写临时文件**（`_temp`）→ **rename 原子替换**
- 读取失败自动回退备份（`_tryRestoreFromBackup`），界面上还给了「恢复损坏文件 / 去重」两个自救按钮
- `fromJson` 对 `points` 的三种历史长度（5 元组 / 4 元组 / 仅经纬度）都做了兼容
- 导入后若 WebDAV 已启用且文件未上云，自动触发上传（`_autoUploadToWebDav`）

### 4.2 `models/kml_parser.dart` — KML 解析（624 行）

`KmlParser.parseKmlFile()` 返回 `{points, markers, name, tags, trackColor, trackWidth}`。覆盖面比较广：

| KML 结构 | 处理方式 |
| --- | --- |
| `Document > Placemark` | 直接解析 |
| `Folder` | 递归；文件夹名含「标注点 / markers / Points」时只取 `Point`，否则按轨迹处理 |
| `Point` | → `KmlMarker`（含 `id`、`TimeStamp/when`、图片 URL、`ExtendedData`） |
| `LineString` | → `List<TrackPoint>`（经纬高） |
| **`gx:Track`** | 两步路主要格式，逐点配对 `gx:coord` 与 `when` |
| **`gx:MultiTrack`** | 拆成多条 `gx:Track` 顺序拼接 |
| `Polygon` | 取 `outerBoundaryIs > LinearRing` 当轨迹 |
| `MultiGeometry` | 按子几何类型分派 |

样式解析：优先 `Style[@id='LineStringStyle']`，退而取 `TrackStyle_n`；KML 颜色是 `AABBGGRR`，代码里手动拆 a/b/g/r 再 `Color.fromARGB(a, r, g, b)`。

标签解析：先找 `Document/ExtendedData/Data[@name='TrackTags']` 的 `value`（会剥掉 CDATA 包裹），再回退到任意 `TrackTags` 元素，用逗号分隔。

> ⚠ 语义注意：`LineString` 本身不带时间，代码用 `TimeStamp`/`TimeSpan` 作基准、按 `i * 30 秒` **合成**时间戳，且 `speed` 一律置 0。所以纯 `LineString` 轨迹的"速度曲线"没有物理意义，只有 `gx:Track` 才带真实时间。

### 4.3 `utils/coord_transform.dart` — 坐标系（94 行）

标准 GCJ-02 偏移算法（`a=6378245.0`、`ee=0.00669342162296594323`），`_outOfChina` 用经纬度矩形兜底，境外坐标原样返回。`gcj02ToWgs84` 用的是"再加一次偏移取反"的近似逆变换。

**何时转换**由 `main.dart` 里一处字符串判断决定：

```dart
final isChineseMap = server.name.contains('高德') || server.name.contains('天地图');
```

也就是说**靠底图名字硬编码判定坐标系**，新增国产底图必须同步改这里。

### 4.4 `main.dart` — 地图主页（2102 行）

一个 `StatefulWidget` 承担了全部：底图管理、网络探测、定位、轨迹渲染、浮动按钮组、诊断面板。值得单独说明的几块：

- **`TileServer` 数据类**（已移到 [tile_server.dart](lib/models/tile_server.dart)）：`name / url / attribution / subdomains / status / visible / isChineseMap`，11 个内置供应商（见第 5 节）。`isChineseMap` 显式标记坐标系，取代原本 `name.contains('高德')` 的字符串判断。
- **健康检查**（已抽到 [tile_probe.dart](lib/services/tile_probe.dart)）：把 `{z}{x}{y}{s}` 换成一组固定值发 HTTP GET，8 秒超时，拿 200 就算可用；结果渲染成绿/红/灰圆点，**只有当"当前选中"的底图不可用**时才自动切换到第一个可用项，不会覆盖用户的手动选择。
- **渲染**（已抽到 [track_renderer.dart](lib/services/track_renderer.dart)）：`PolylineLayer` 画轨迹，`MarkerLayer` 画标注点（有图片的显示红色相机图标，起点/终点是绿色三角，其余蓝色图钉），点击标注点弹 `MarkerInfoDialog`。
- **跳转到轨迹** `_jumpToTrack`：用 `CameraFit.bounds` 适配视野（原先手算包围盒的代码复制了三份，现已合并为一个 `boundsOf`），命中轨迹加粗 2px，5 秒后复原。
- **定位**（已抽到 [location_controller.dart](lib/controllers/location_controller.dart)）：`Geolocator.getPositionStream`，**间隔真正生效**（见第 9 节修复项），精度/速度/更新时间显示在左上角卡片。
- **状态持久化**（已抽到 [settings_service.dart](lib/services/settings_service.dart)）：键名集中管理，首次运行写入默认可见性。
- **诊断面板**：网络状态、当前底图、坐标系、底图可用/可见数、缩放/中心、定位状态、文件数。

### 4.5 `pages/file_manager_page.dart` — 文件管理（914 行）

- 导入：`file_picker` 选 `.kml`，同名先问「是否覆盖」，成功后刷新并通知主界面。
- 列表卡片：左侧色条 = 轨迹颜色；标题 = 去掉 `2025-06-02 10:28` 这类日期前缀后的名字；副标题 = `PosStartName-PosEndName` 精简结果 + 轨迹时间 + 标签 chip；右侧是云端状态灯、可见性、上传/编辑/显隐/删除四个小按钮。
- **标签筛选**：用 `FilterChip` 多选，筛选不只改列表，还会**批量改写文件可见性**（`_updateFileVisibilityForTags`），让地图跟着变。
- **去重** `_removeDuplicates`：先按文件名（忽略大小写）分组，保留 `importDate` 最新的一条；找不到再退化成「内容长度+点数」伪哈希比对。
- 大文件保护：点数 > 50000 时先弹警告再进编辑。

### 4.6 `pages/track_edit_dialog.dart` — 轨迹编辑弹窗（477 行）★实际生效的编辑器

一个 90%×80% 的 `Dialog`，四块内容：

1. 显示名输入框；
2. 颜色（`flutter_colorpicker` 取色器）+ 线宽（1–10 滑块）；
3. **`fl_chart` 曲线图**：`YAxisType` 枚举支持 `海拔 / 速度 / 里程` 三种纵轴；速度优先用 KML 里的值，缺失时用前后点距离/时间做**双侧平均**；里程是逐点累加的 Haversine 距离；
4. `RangeSlider` 选起止点（点数 > 1000 时 `divisions` 降为 100 防卡顿）。

保存时只在 `KmlFileManager.updateFileStyle` 里更新元数据字段（**不回写 KML 原文件**）。

### 4.7 `pages/track_edit_page.dart` — 整页版编辑器（524 行）☆死代码

功能是弹窗版的超集：`CustomPainter`（`TrackPreviewPainter`）做缩略图预览、按画布宽度采样降点、> 10000 点时改用「直接输入起止索引」+ 100ms 防抖。**但全项目没有任何地方引用 `TrackEditPage`**，`file_manager_page.dart` 用的是 `TrackEditDialog`。这是一次未收尾的重构遗留。

### 4.8 `services/webdav_service.dart` + 两个 WebDAV 页面

单例 `WebDavService.instance`，配置存在 `SharedPreferences`（`webdav_enabled / url / username / password / path`，默认远端目录 `/kml_files`）。

| 能力 | 实现 |
| --- | --- |
| 上传 | 先 `_exists` 判重（存在就跳过、返回 false），再 `mkdirAll` 确保目录，最后 `writeFromFile` |
| 下载 | `read2File` 落到系统临时目录 |
| 列目录 | `readDir` 后只保留 `.kml` |
| 连通性 | `ping()` |
| 去重 | 按去掉 `kml_explorer<hex>_`/`temp_`/`tmp_` 前缀后的基名分组，保留"最新"一条 |

界面侧：[webdav_settings_page.dart](lib/pages/webdav_settings_page.dart) 填 URL/账号/密码/路径 + 测试连接 + 清理重复；[webdav_file_picker_page.dart](lib/pages/webdav_file_picker_page.dart) 是多选下载页，带「已加载」标记、全选、逐文件 `LinearProgressIndicator`，并在下载前过滤掉本地同名文件。

### 4.9 `services/permission_service.dart` — 权限（36 行）

三步走：定位服务是否开启 → `checkPermission/requestPermission` → 若为 Android 且 `sdkInt >= 33`，再要一次 `requestTemporaryFullAccuracy`。

---

## 5. 内置地图供应商

| # | 名称 | 坐标系 | 备注 |
| --- | --- | --- | --- |
| 1 | OpenStreetMap | WGS-84 | 默认首选 |
| 2 | 高德地图 | GCJ-02 | 自动转换坐标 |
| 3 | 高德卫星 | GCJ-02 | 自动转换坐标 |
| 4 | 天地图矢量 `vec_w` | GCJ-02 | **需 API Key** |
| 5 | 天地图影像 `img_w` | GCJ-02 | **需 API Key** |
| 6 | 天地图地形 `ter_w` | GCJ-02 | **需 API Key** |
| 7 | CartoDB Positron | WGS-84 | |
| 8 | CartoDB Dark Matter | WGS-84 | |
| 9 | OpenTopoMap | WGS-84 | |
| 10 | CyclOSM | WGS-84 | |
| 11 | Esri World Imagery | WGS-84 | |

> 原先还有 Stamen Terrain / Stamen Watercolor 两项，但 Stamen 官方已停止 fastly 托管、这些 URL 实际返回 410，本次已移除。

- **天地图 Key**：代码里是占位串 `你的天地图密钥`，在「设置 → 天地图密钥」里填写后由 `MapConfig.getTiandituUrl()` 替换 `tk=` 参数并持久化。未配密钥时探测会直接标记为「未配置天地图 API Key」，不再徒劳发请求。
- **可选可见性**：11 个不必全显示，可以在「设置 → 地图供应商」里勾选只留常用的几个（选择器只列可见项）。
- `TileLayer` 统一 `minZoom: 3 / maxZoom: 18 / keepBuffer: 2`。原先挂的 1×1 透明 `fallbackUrl` 已移除——它让 404 静默无痕，反而掩盖了底图失效；现在加载失败可见，也可从诊断面板查看具体错误。

---

## 6. 数据流

### 导入

```
file_picker 选文件
  → KmlFileManager.saveKmlFile()
       ├─ 复制到 <文档目录>/kml_files/<安全文件名>
       ├─ KmlParser.parseKmlFile() 解析（失败也要能落地，不阻塞）
       ├─ KmlFile 入元数据 JSON（原子写 + 备份）
       └─ WebDAV 已启用 → _autoUploadToWebDav() → updateCloudStatus(true)
  → FileManagerPage 刷新 → onFilesChanged → MapPage._rebuildLayers()
       └─ TrackRenderer 按当前底图决定是否做 GCJ-02 转换 → 重建 Polyline / Marker
```

### 关键设计点

- **元数据是唯一真相源**：颜色、线宽、起止点、显示名、可见性、标签全在 JSON 里；KML 原文只在导入时被读取一次。
- **KML 原文保底**：「恢复损坏文件」和「去重」都依赖磁盘上的原始 KML，所以 `kml_files/` 目录不能随便删。
- **坐标转换发生在渲染层**：模型统一存 WGS-84，只有喂给地图前才转换。

---

## 7. 依赖清单

直接依赖（`pubspec.yaml` 声明），"版本"列是 `pubspec.lock` 实际锁定值：

| 依赖 | 版本 | 用途 |
| --- | --- | --- |
| `flutter_map` | 6.2.1 | 瓦片地图与图层（`PolylineLayer`/`MarkerLayer`） |
| `latlong2` | 0.9.1 | `LatLng`、`Distance`（Haversine） |
| `xml` | 6.5.0 | KML XML 解析 |
| `geolocator` | 12.0.0 | 定位与位置流 |
| `permission_handler` | 11.4.0 | 权限（实际申请走 `geolocator`，此包未直接调用） |
| `device_info_plus` | 10.1.2 | 读 Android SDK 版本以判断精确位置权限 |
| `file_picker` | 8.3.7 | 选 `.kml` 文件 |
| `path_provider` | 2.1.5 | 应用文档目录 |
| `shared_preferences` | 2.5.3 | 底图选择/可见性、天地图 Key、WebDAV 配置 |
| `http` | 1.4.0 | 网络探测与瓦片健康检查 |
| `flutter_colorpicker` | 1.1.0 | 轨迹颜色取色 |
| `fl_chart` | 0.70.2 | 海拔/速度/里程折线图 |
| `webdav_client` | 1.2.2 | WebDAV 读写 |
| `path` | 1.9.1 | 路径拼接（WebDAV 远端路径） |
| `flutter_lints` | 5.0.0 | 静态检查（dev） |

各平台实际注册的原生插件（来自 `.flutter-plugins-dependencies`）：Android / iOS / Windows / macOS / Web 均覆盖 `file_picker`、`device_info_plus`、`path_provider`、`shared_preferences`、`geolocator`；**Linux 缺 `geolocator` 与 `permission_handler`**，所以 Linux 上定位相关功能不可用。

---

## 8. 平台相关配置

**Android**（[AndroidManifest.xml](android/app/src/main/AndroidManifest.xml)）

- 权限：`INTERNET`、网络状态、`READ/WRITE_EXTERNAL_STORAGE`、**`MANAGE_EXTERNAL_STORAGE`**、**前后台定位**、`CAMERA`、`CHANGE_NETWORK_STATE`
- `android:usesCleartextTraffic="true"`（允许明文 HTTP，自建 WebDAV 用得上，但也是安全放宽）
- `android:requestLegacyExternalStorage="true"`（Android 10 兼容老式存储）
- 注册了 KML/KMZ/XML 的 `ACTION_VIEW` intent-filter，可从文件管理器直接打开
- `FileProvider` + [file_paths.xml](android/app/src/main/res/xml/file_paths.xml)
- Gradle：AGP 8.7.3 / Kotlin 2.1.0 / Gradle 8.12 / JVM 17；minSdk 24 / targetSdk 35 / compileSdk 35
- 依赖仓库在 [settings.gradle.kts](android/settings.gradle.kts) 的 `dependencyResolutionManagement` 中声明（**不要**写 `allprojects { repositories }`，见第 2.3 节坑 2）
- 未声明 `ndkVersion`：本项目无自定义 C/C++ 代码，也无插件带 `CMakeLists.txt`，声明 NDK 只会让 AGP 为空跑 CMake 并在 `mergeReleaseNativeLibs` 卡住
- 签名：口令从 `android/key.properties` 读取，该文件与 `*.jks` 均已在 `.gitignore` 中（故仓库内不含此文件）；无该文件时显式退回 debug 签名

**Windows**（[windows/runner/main.cpp](windows/runner/main.cpp)）窗口标题 `kml_explorer`，初始 1280×720。

**Web**：脚手架齐全但定位、文件系统、`dart:io` 依赖较重，不建议作为主目标平台。

---

## 9. 已知问题与技术债

按影响排序。其中「已解决」条目保留记录，便于追溯重构收益。

### ✅ 已解决（本次）

1. ~~项目根本编译不过：3 个 geolocator API 错误~~ —— `intervalDuration`/`fastestIntervalDuration` 只存在于 `AndroidSettings`，已按平台分别构造；`LocationAccuracyStatus.granted` 改为 `precise`/`reduced` 判断。
2. ~~`test/widget_test.dart` 是失效的模板测试~~ —— 已删除，改为 `kml_parser_test.dart` 与 `coord_transform_test.dart` 两组共 12 个真实测试。
3. ~~位置更新间隔设置是空的~~ —— 用户选的间隔现在真正传入 `AndroidSettings.intervalDuration`，并在修改后自动重启位置流。
4. ~~Android release 签名配错~~ —— 改为「有 `key.properties` 就用 release 签名，否则显式退回 debug」，不再静默混淆。原 keystore 口令实际已失效（`keytool` 报 password incorrect），已重新生成。
5. ~~凭据硬编码入库~~ —— 口令移入 `key.properties`，该文件与 `*.jks` 均已列入 `.gitignore`。
6. ~~坐标系判定靠底图名字字符串~~ —— 改由 `TileServer.isChineseMap` 显式标注。
7. ~~`main.dart` 2102 行单体~~ —— 拆为 `pages/map_page.dart`（约 820 行 UI）、`controllers/location_controller.dart`、`services/{settings_service,tile_probe,track_renderer}.dart`、`pages/tile_server_dialogs.dart`，入口只剩 24 行。
8. ~~WebDAV "保留最新"失效~~ —— `listFiles()` 原先写死 `DateTime.now()`，已改用 `file.mTime`。
9. ~~`_exists()` 重复 readDir~~ —— 合并为一次。
10. ~~底图加载失败静默~~ —— 移除 1×1 透明兜底图，失败可见；未配天地图密钥时也提前判定，不再发无效请求。
11. ~~构建跑不通~~ —— Gradle 8.12 + 国内镜像 + 移除多余 NDK + 关闭 lint，现可稳定出包（详见第 2.3 节）。

### 🔴 仍需处理

1. **WebDAV 密码明文存放**：凭据以明文写在 `SharedPreferences` 中，建议改用 `flutter_secure_storage`。
2. **无 KML 导出/回写**：所有编辑只落元数据，原始 KML 永不更新，无法把改好的轨迹带回其它 App。
3. **`applicationId` 仍是 `com.example.kml_explorer`**：上架前必须换成自己的域名反写，且一旦发布不可再改。

### 🟡 逻辑不严谨

4. **`LineString` 的速度全是 0、时间戳是合成的**（`i * 30s`，见 `kml_parser.dart:450/527/583`），导致速度曲线与「轨迹时间」对这类文件没有参考价值。仅 `gx:Track` 带真实时间。
5. **`deleteFile`/`uploadFile` 多数失败分支只 `debugPrint`**，UI 拿不到具体原因。

### 🟢 结构问题

6. **`TrackEditPage` 是死代码**（无任何 import 引用），与 `TrackEditDialog` 功能重复，应删除或接回界面。
7. **序列化方式脆弱**：`KmlFile.toJson` 把标注点写成**定长位置数组**（`marker[11]` 取 `extendedData`，见 `kml_file.dart:286`），字段一改就崩，建议换具名 Map 或 `json_serializable`。
8. **状态管理仍靠层层回调**：`onFilesChanged / onTrackSelected / onFilteredFilesChanged` 三条线手工串联，可考虑引入 Provider / Riverpod。

---

## 10. 如果要继续改，建议顺序

1. 删掉或接回 `TrackEditPage`，别让两份编辑器并行腐化。
2. 给 `KmlFile.toJson` 换成具名 Map 序列化（或 `json_serializable`），顺带补 `migrationVersion` 字段。
3. WebDAV 密码迁移到 `flutter_secure_storage`。
4. 补 KML 导出（把 `startPointIndex..endPointIndex` 与样式写回新 `.kml`）。
5. 引入状态管理承接 `KmlFile` 列表，去掉三线回调。
6. `LineString` 的速度/时间戳按真实数据推导，而非合成值。

---

## 11. 参考资料

> `reference/` 目录（OGC 规范 PDF 与个人轨迹样本）仅保留在本地，已列入 `.gitignore`，不随仓库分发。

- OGC KML 2.2 规范（本地 `reference/07-147r2_OGC_KML_2.2.pdf`）
- 本地示例数据（`reference/`）：东莞长安莲花山轨迹（含 `gx:Track` + 图片标注点）、鲲鹏径一至十一段合并（含多段 `LineString`）
- [flutter_map 文档](https://docs.fleaflet.dev/) · [fl_chart](https://github.com/imaNNeo/fl_chart) · [geolocator](https://pub.dev/packages/geolocator)
- 天地图密钥申请：<https://console.tianditu.gov.cn/api/key>
