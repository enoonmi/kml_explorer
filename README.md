# KML Explorer

> 一个用来**管理与查看 KML 轨迹文件**的 Flutter 跨平台应用：多地图供应商在线底图、轨迹解析与渲染、轨迹样式/区间编辑、图片标注点浏览、实时定位、以及 WebDAV 云同步。

- **包名 / 应用名**：`kml_explorer`（v1.0.0）
- **技术栈**：Flutter + Dart（`sdk: ^3.8.1`，`flutter: >=3.29.0`）
- **代码规模**：`lib/` 下 14 个 Dart 文件，约 7000 行
- **目标平台**：Android / iOS / Windows / macOS / Linux / Web（工程脚手架齐全，实际以 Android + Windows 为主）

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

```bash
cd kml_explorer

flutter pub get

# 桌面 / 手机
flutter run -d windows      # 或在 VS Code 里选设备
flutter run -d chrome
flutter run -d <android-device>

# 打包
flutter build windows --release
flutter build apk --release
```

**前置条件**

- Flutter 3.29+（工程由 Flutter stable 分支 `6fba2447` 创建，见 [.metadata](.metadata)）
- Android 打包需要 [android/local.properties](android/local.properties) 里的 `flutter.sdk` 指向本机 Flutter 目录
- 使用天地图底图需要自行申请 API Key（见第 5 节）

**首次运行注意**

- 桌面端左侧会并排显示文件管理面板（固定宽 320，`AnimatedSwitcher` 动画），移动端只显示地图；可用 AppBar 最右侧按钮收起/展开面板。
- 启动时会先做网络探测、再逐个测试 13 个瓦片服务器，因此**前几秒地图可能还是一片"地图加载中…"**，属正常行为。

---

## 3. 目录结构

```
kml_explorer/
├── lib/                        # 全部业务代码（约 7000 行）
│   ├── main.dart               # 应用入口 + 地图主页（约 2100 行，最大单文件）
│   ├── models/                 # 数据模型与持久化
│   │   ├── kml_file.dart       # 轨迹文件模型 + KmlFileManager（元数据 CRUD/备份）
│   │   ├── kml_parser.dart     # KML XML 解析器（TrackPoint 也定义在此）
│   │   ├── kml_marker.dart     # 标注点模型（图片/扩展数据）
│   │   └── map_config.dart     # 天地图 API Key 的存取
│   ├── pages/                  # 界面
│   │   ├── file_manager_page.dart      # KML 文件列表、标签筛选、导入/删除/去重
│   │   ├── track_edit_dialog.dart      # 轨迹编辑弹窗（曲线图 + 区间滑块）★实际使用
│   │   ├── track_edit_page.dart        # 轨迹编辑整页版（含 Canvas 预览）☆未被引用
│   │   ├── marker_info_dialog.dart     # 标注点详情（在线图片 + 扩展数据）
│   │   ├── webdav_settings_page.dart   # WebDAV 服务器配置
│   │   └── webdav_file_picker_page.dart # WebDAV 远端文件多选下载
│   ├── services/
│   │   ├── webdav_service.dart  # WebDAV 单例：上传/下载/列目录/去重
│   │   └── permission_service.dart # 定位权限申请（含 Android 13+ 精确位置）
│   └── utils/
│       └── coord_transform.dart # WGS-84 ⇄ GCJ-02 坐标转换
├── android/                    # Android 工程（Gradle Kotlin DSL、keystore、权限声明）
├── ios/  macos/  linux/  windows/  web/   # 各平台脚手架
├── reference/                  # 调试用素材
│   ├── 2025-06-0210_28东莞长安莲花山.kml
│   ├── 鲲鹏径一到十一段（合并）.kml
│   └── 07-147r2_OGC_KML_2.2.pdf       # OGC KML 2.2 规范
├── test/widget_test.dart       # ⚠ 仍是模板自带的计数器测试（已失效）
├── build/  .dart_tool/  .idea/  .vscode/ # 构建产物与编辑器配置（未清理）
├── pubspec.yaml  pubspec.lock
└── analysis_options.yaml       # flutter_lints 默认规则
```

> 项目**没有 git 仓库**（无 `.git/`、无提交历史），因此无法回溯逐次改动。从 `.idea/`（2025-06-18 创建）与 `.vscode/` 并存可以看出它是在 IDE 里由 AI 编程助手迭代出来的，但目录里没有任何能指认 Trae 或 Claude Code 的元数据（无 `.trae/`、无 `CLAUDE.md`）。**代码风格线索**：全中文注释与 UI 文案、`debugPrint` 大量保留、注释里出现 `// 新增：`、`// 删除此行: geolocator: ^10.1.0`、`// 修复方法名引用错误` 这类"改动留痕"式注释，以及 `main.dart` 单体式膨胀——这些都更像"边聊边改"的迭代产物，而不是先设计后编码。如果是想确认工具，只能按时间线（2025-06-18 建工程 → 2025-06-21 完成主体 → 2025-12-13 做了一轮依赖与入口修补）去比对当时的编辑器记录。

### 时间线（按文件修改时间）

| 时间 | 内容 |
| --- | --- |
| 2025-06-18 20:20 | Flutter 工程脚手架生成（`.metadata`、`.gitignore`、`.idea`） |
| 2025-06-20 | 轨迹编辑页 → 天地图配置 → 坐标转换 → 标注点模型 → 解析器 |
| 2025-06-21 19:xx | 文件管理页、WebDAV 三个文件、`kml_file.dart`（主体功能收尾） |
| 2025-12-12 ~ 12-13 | 重写 README、调 `pubspec.yaml` 依赖、改 `main.dart` 与权限服务 |

---

## 4. 架构与模块职责

采用最朴素的 Flutter 分层（无状态管理框架、无路由框架、无依赖注入）：**models 管数据、services 管外部 IO、pages 管界面、main.dart 当胶水层**。

```
                 ┌────────────────────────────────────┐
                 │        main.dart  (MapPage)        │
                 │  地图 / 底图 / 定位 / 菜单 / 诊断    │
                 └───┬───────────┬────────────┬───────┘
                     │           │            │
        回调通知       │           │ 弹窗        │ 导航
                     ▼           ▼            ▼
        FileManagerPage   TrackEditDialog   WebDavSettingsPage
        (列表/筛选/可见性)  (曲线图/区间/样式)  WebDavFilePickerPage
                     │           │            │
                     └───────────┴────────────┘
                                 │
                        KmlFileManager（元数据 JSON CRUD/备份）
                           │                    │
                 KmlParser ┘                    └ WebDavService（单例）
                     │
        KmlFile / TrackPoint / KmlMarker
                     │
        CoordTransform（WGS-84 ⇄ GCJ-02）
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

- **`TileServer` 数据类**：`name / url / attribution / subdomains / status / visible`，13 个内置供应商（见第 5 节）。
- **健康检查**：把 `{z}{x}{y}{s}` 换成一组固定值发 HTTP GET，8 秒超时，拿 200 就算可用；结果渲染成绿/红/灰圆点，**只有当"当前选中"的底图不可用**时才自动切换到第一个可用项，不会覆盖用户的手动选择（这点做得对）。
- **渲染**：`PolylineLayer` 画轨迹，`MarkerLayer` 画标注点（有图片的显示红色相机图标，起点/终点是绿色三角，其余蓝色图钉），点击标注点弹 `MarkerInfoDialog`。
- **跳转到轨迹** `_jumpToTrack`：用转换后的坐标算包围盒 → 取 `optimalZoom` → `move`，并把命中轨迹加粗 2px，5 秒后复原。
- **定位**：`Geolocator.getPositionStream`，`accuracy: high`、`distanceFilter: 5`，精度/速度/更新时间显示在右上角卡片。
- **状态持久化**：`SharedPreferences` 的 `tile_server_index` 与 `tile_server_visible_$i`；首次运行会写入全部可见。
- **诊断面板**：网络状态、地图控制器、底图可用数、当前缩放/中心、定位状态、已加载文件数。

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
| 12 | Stamen Terrain | WGS-84 | ⚠ Stamen 已迁出 fastly，可能失效 |
| 13 | Stamen Watercolor | WGS-84 | ⚠ 同上 |

- **天地图 Key**：代码里是占位串 `你的天地图密钥`，在「设置 → 地图供应商设置 → 天地图设置」里填写后由 `MapConfig.getTiandituUrl()` 替换 `tk=` 参数并持久化。
- **可选可见性**：13 个不必全显示，可以在设置里勾选只留常用的几个（选择器只列可见项）。
- `TileLayer` 统一 `minZoom: 3 / maxZoom: 18 / keepBuffer: 2`，并挂了一张 **1×1 透明 PNG 的 `fallbackUrl`** ——瓦片 404 时不会出现红叉，但也意味着**加载失败是"静默"的**，排查问题得看诊断面板。

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
  → FileManagerPage 刷新 → onFilesChanged → MapPage._updatePolylines()
       └─ 按当前底图决定是否做 GCJ-02 转换 → 重建 Polyline / Marker
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
- Gradle：AGP 8.7.3 / Kotlin 2.1.0 / NDK 27.0.12077973 / JVM 11；仓库预置阿里云镜像（[settings.gradle.kts](android/settings.gradle.kts)）

**Windows**（[windows/runner/main.cpp](windows/runner/main.cpp)）窗口标题 `kml_explorer`，初始 1280×720。

**Web**：脚手架齐全但定位、文件系统、`dart:io` 依赖较重，不建议作为主目标平台。

---

## 9. 已知问题与技术债

按影响排序，供后续重构参考：

### 🔴 会直接影响功能

1. **`test/widget_test.dart` 是失效的模板测试**：断言 `find.text('0')`、点 `Icons.add`，而 `MyApp` 里根本没有计数器。`flutter test` 必然失败。
2. **位置更新间隔设置是空的**：`_locationUpdateInterval` 只用于提示文案和重启流，但 `LocationSettings` 里写死 `intervalDuration: 5s`、`fastestIntervalDuration: 1s`、`distanceFilter: 5`，**用户在「位置设置」里选 1/3/10/30 秒不会生效**。
3. **Android release 签名配错**：`buildTypes.release` 用的是 `signingConfigs.getByName("debug")`，虽然上面定义了 `signingConfigs.create("release")` 却没用上 —— 打出来的 release 包是 debug 签名的。
4. **凭据以明文入库**：[build.gradle.kts](android/app/build.gradle.kts) 里硬编码了 keystore 密码 `kml_explorer_2024`（且 `kml_explorer.keystore` 就在仓库里）；WebDAV 密码也是明文存 `SharedPreferences`。

### 🟡 逻辑不严谨

5. **`LineString` 的速度全是 0、时间戳是合成的**（`i * 30s`），导致速度曲线与"轨迹时间"对这类文件没有参考价值。
6. **WebDAV 重复清理的"保留最新"失效**：`listFiles()` 把 `lastModified` 一律写成 `DateTime.now()`，排序结果随机。
7. **`_exists()` 连续调了两次 `readDir`**，多一次无用往返。
8. **失败被静默吞掉**：瓦片挂了有 1×1 透明 PNG 兜底，`deleteFile`/`uploadFile` 多数分支只 `debugPrint` 不抛错。
9. **坐标系判定靠底图名字字符串**（`contains('高德')`/`contains('天地图')`），新增供应商容易漏改。

### 🟢 结构问题

10. **`main.dart` 2102 行单体**，UI、业务、网络、持久化全在一个 State 里；无状态管理、无路由表、无依赖注入，`setState` 到处飞。
11. **`TrackEditPage` 是死代码**（524 行，无引用），与 `TrackEditDialog` 功能重复。
12. **序列化方式脆弱**：`KmlFile.toJson` 把标注点写成**定长位置数组**（`marker[11]` 取 `extendedData`），字段一改就崩；`KmlMarker.fromJson`、`TileServer.fromJson` 也不被主流程使用。
13. **无 KML 导出/回写**：所有编辑只落元数据，原始 KML 永不更新，也就无法把改好的轨迹带回其它 App。
14. **`webdav_client` 之外还散落 `http` 直连**（网络探测打 `httpbin.org`），启动阶段多一次外部依赖。
15. **仓库卫生**：`build/`（含 NuGet 包与 CMake 缓存）、`.dart_tool/`、`.idea/`、`.vscode/` 都在目录里；[.vscode/settings.json](.vscode/settings.json) 里的 `cmake.sourceDirectory` 还指向旧路径 `D:/code/explorer/kml_explorer/windows`（实际是 `D:/code/kml_explorer/windows`）。且**整个项目不在版本控制下**。

---

## 10. 如果要继续改，建议顺序

1. 先修「三件小事」：删掉/重写 `widget_test.dart`、release 签名改用 `release` 配置、让位置间隔真正传入 `LocationSettings`。
2. 把 `main.dart` 拆出去：`tile_server_manager`（底图与健康检查）、`location_controller`、`track_renderer`（坐标转换 + 图层构建）、`map_page`（只剩 UI）。
3. 引入状态管理（Provider / Riverpod 均可）承接 `KmlFile` 列表，去掉层层回调（现在 `onFilesChanged / onTrackSelected / onFilteredFilesChanged` 三条线手工串）。
4. 给 `KmlFile.toJson` 换成具名 Map 序列化（或 `json_serializable`），顺带补一个 `migrationVersion` 字段。
5. 视需要加 KML 导出（把当前 `startPointIndex..endPointIndex` 与样式写回一个新 `.kml`）。
6. 想留 `TrackEditPage` 就接进界面，不想留就删除，别让两份编辑器并行腐化。

---

## 11. 参考资料

- [OGC KML 2.2 规范](reference/07-147r2_OGC_KML_2.2.pdf)（就在 `reference/` 里）
- 示例数据：[东莞长安莲花山轨迹](reference/2025-06-0210_28东莞长安莲花山.kml)（含 `gx:Track` + 图片标注点）、[鲲鹏径一至十一段合并](reference/鲲鹏径一到十一段（合并）.kml)（含 `TbuluLineStringFolder` 多段 `LineString`）
- [flutter_map 文档](https://docs.fleaflet.dev/) · [fl_chart](https://github.com/imaNNeo/fl_chart) · [geolocator](https://pub.dev/packages/geolocator)
- 天地图密钥申请：<https://www.tianditu.gov.cn/>
