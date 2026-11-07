# 一键配置 KML Explorer 的 Flutter / Android 开发环境
#
# 用法：
#   pwsh -File scripts/setup_env.ps1          # 只检测并报告
#   pwsh -File scripts/setup_env.ps1 -Build   # 检测后直接构建 release APK
#
# 本机实测可用的路径（如换了机器请改这里的默认值）：
#   Flutter : D:\ProgramData\flutter  (3.32.4 / Dart 3.8.1)
#   JDK 17  : C:\Users\<user>\.jdks\tmp17\jdk-17.0.2
#   Android : C:\Users\<user>\AppData\Local\Android\Sdk

param(
    [string]$FlutterHome = 'D:\ProgramData\flutter',
    [string]$JdkHome,
    [string]$AndroidHome,
    [switch]$Build,
    [switch]$SkipAnalyze
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

function Find-Jdk {
    $candidates = @(
        $env:JAVA_HOME,
        'C:\Users\' + $env:USERNAME + '\.jdks\tmp17\jdk-17.0.2',
        'C:\Users\' + $env:USERNAME + '\.jdks\jdk-17.0.2',
        'C:\Program Files\Java\jdk-17',
        'C:\Program Files\Eclipse Adoptium\jdk-17*'
    ) | Where-Object { $_ }

    foreach ($c in $candidates) {
        $resolved = Get-ChildItem -Path $c -ErrorAction SilentlyContinue -Directory |
            Select-Object -First 1
        $path = if ($resolved -and $c -match '\*') { $resolved.FullName } else { $c }
        # 必须是完整 JDK：既有 javac，也有 lib\jvm.cfg
        if ((Test-Path (Join-Path $path 'bin\javac.exe')) -and
            (Test-Path (Join-Path $path 'lib\jvm.cfg'))) {
            return $path
        }
    }
    return $null
}

function Find-AndroidSdk {
    $candidates = @(
        $env:ANDROID_HOME,
        $env:ANDROID_SDK_ROOT,
        'C:\Users\' + $env:USERNAME + '\AppData\Local\Android\Sdk',
        'C:\Android\Sdk'
    ) | Where-Object { $_ }

    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c 'platform-tools\adb.exe')) { return $c }
    }
    return $null
}

Write-Host '=== 1. 检测 Flutter ===' -ForegroundColor Cyan
$flutterBat = Join-Path $FlutterHome 'bin\flutter.bat'
if (-not (Test-Path $flutterBat)) {
    Write-Host "找不到 Flutter：$flutterBat" -ForegroundColor Red
    Write-Host '请修改 -FlutterHome 或安装 Flutter 3.32.x。'
    exit 1
}
Write-Host "OK  $flutterBat"

Write-Host '=== 2. 检测 JDK 17 ===' -ForegroundColor Cyan
if (-not $JdkHome) { $JdkHome = Find-Jdk }
if (-not $JdkHome) {
    Write-Host '找不到可用的 JDK 17（需要 javac 与 lib\jvm.cfg）。' -ForegroundColor Red
    Write-Host '安装：winget install EclipseAdoptium.Temurin.17.JDK'
    exit 1
}
Write-Host "OK  $JdkHome"

Write-Host '=== 3. 检测 Android SDK ===' -ForegroundColor Cyan
if (-not $AndroidHome) { $AndroidHome = Find-AndroidSdk }
if (-not $AndroidHome) {
    Write-Host '找不到 Android SDK。' -ForegroundColor Red
    Write-Host '建议安装 Android Studio，或设置 ANDROID_HOME。'
    exit 1
}
Write-Host "OK  $AndroidHome"

# 汇总到当前进程环境
$env:JAVA_HOME = $JdkHome
$env:ANDROID_HOME = $AndroidHome
$env:ANDROID_SDK_ROOT = $AndroidHome
$env:PATH = "$JdkHome\bin;$FlutterHome\bin;$env:PATH"

Write-Host '=== 4. 写入 android/local.properties ===' -ForegroundColor Cyan
$localProps = Join-Path $repoRoot 'android\local.properties'
$sdkEscaped = $AndroidHome.Replace('\', '\\')
$flutterEscaped = $FlutterHome.Replace('\', '\\')
@(
    "sdk.dir=$sdkEscaped"
    "flutter.sdk=$flutterEscaped"
) | Set-Content -Path $localProps -Encoding ascii
Write-Host "OK  $localProps"

Write-Host '=== 5. flutter pub get ===' -ForegroundColor Cyan
Push-Location $repoRoot
try {
    & $flutterBat pub get
    if ($LASTEXITCODE -ne 0) { throw 'pub get 失败' }

    if (-not $SkipAnalyze) {
        Write-Host '=== 6. flutter analyze ===' -ForegroundColor Cyan
        & $flutterBat analyze
    }

    Write-Host '=== 7. flutter test ===' -ForegroundColor Cyan
    & $flutterBat test

    if ($Build) {
        Write-Host '=== 8. 构建 release APK ===' -ForegroundColor Cyan
        & $flutterBat build apk --release
        if ($LASTEXITCODE -eq 0) {
            $apk = Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-release.apk'
            if (Test-Path $apk) {
                $size = [math]::Round((Get-Item $apk).Length / 1MB, 2)
                Write-Host "APK: $apk  ($size MB)" -ForegroundColor Green
            }
        }
    }
}
finally {
    Pop-Location
}

Write-Host ''
Write-Host '环境就绪。常用命令：' -ForegroundColor Green
Write-Host '  flutter run -d <device-id>     # 调试运行'
Write-Host '  flutter build apk --release    # 打包'
Write-Host '  flutter devices                # 查看设备'
