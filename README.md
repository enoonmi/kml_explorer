# KML Explorer - KML轨迹文件管理和查看器

## 项目简介

KML Explorer 是一个功能强大的 Flutter 应用程序，专门用于管理和查看 KML（Keyhole Markup Language）轨迹文件。该应用支持多种地图供应商，提供丰富的轨迹编辑功能，并支持云端存储和同步。

## 主要功能

### 🗺️ 多地图供应商支持
- **OpenStreetMap**: 开源地图，全球覆盖
- **高德地图**: 中国地区详细地图和卫星影像
- **天地图**: 中国官方地图服务（矢量、影像、地形）
- **CartoDB Positron**: 简洁美观的地图样式
- **其他瓦片服务器**: 支持自定义瓦片服务器配置

### 📁 文件管理功能
- **本地文件导入**: 支持从本地设备导入 KML 文件
- **WebDAV 云端同步**: 支持 WebDAV 协议，实现云端文件存储和同步
- **文件分类管理**: 基于标签的文件分类和筛选
- **批量操作**: 支持批量导入、删除和管理文件

### 🎯 轨迹显示和编辑
- **多轨迹显示**: 同时显示多个轨迹文件
- **轨迹样式自定义**: 支持自定义轨迹颜色、宽度和显示名称
- **轨迹分段显示**: 支持设置轨迹的起始点和结束点
- **实时编辑**: 在线编辑轨迹点、删除点和修改属性

### 📍 标记点管理
- **标记点显示**: 显示轨迹中的关键标记点
- **详细信息**: 显示标记点的位置、时间、速度等信息
- **自定义标记**: 支持添加自定义标记点和描述

### 🔧 高级功能
- **坐标系自动转换**: 自动处理 WGS-84 和 GCJ-02 坐标系转换
- **位置服务**: 获取当前设备位置并在地图上显示
- **轨迹统计**: 显示轨迹的距离、时间、速度等统计信息
- **权限管理**: 智能处理文件访问和位置权限

## 技术架构

### 项目结构
```
lib/
├── main.dart                 # 应用程序入口和主界面
├── models/                   # 数据模型
│   ├── kml_file.dart        # KML文件数据模型
│   ├── kml_parser.dart      # KML文件解析器
│   ├── kml_marker.dart      # 标记点数据模型
│   └── map_config.dart      # 地图配置
├── pages/                    # 页面组件
│   ├── file_manager_page.dart           # 文件管理页面
│   ├── track_edit_dialog.dart           # 轨迹编辑对话框
│   ├── track_edit_page.dart             # 轨迹编辑页面
│   ├── marker_info_dialog.dart          # 标记点信息对话框
│   ├── webdav_settings_page.dart        # WebDAV设置页面
│   └── webdav_file_picker_page.dart     # WebDAV文件选择页面
├── services/                 # 服务层
│   ├── webdav_service.dart   # WebDAV服务
│   └── permission_service.dart # 权限管理服务
└── utils/                    #