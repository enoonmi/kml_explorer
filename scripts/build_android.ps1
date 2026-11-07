# 一键构建 Android APK（含国内镜像与正确 JDK 设置）
#
# 用法：
#   pwsh -File scripts/build_android.ps1                 # release APK
#   pwsh -File scripts/build_android.ps1 -Split          # 按 ABI 拆分（体积更小）
#   pwsh -File scripts/build_android.ps1 -AppBundle      # 出 .aab（上架用）
#
# 为什么需要这个脚本：本机有三个坑，缺一个就构不出包。
#   1. Flutter 引擎产物在 storage.googleapis.com，国内直连会 "Connection reset"，
#      必须设 FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
#   2. Gradle 全局 init.gradle 曾用 allprojects{repositories{}} 注入阿里云镜像，
#      与 Flutter 插件的 FAIL_ON_PROJECT_REPOS 冲突，构建直接失败
#   3. JAVA_HOME 需指向完整 JDK 17（要有 javac 与 lib\jvm.cfg）

param(
    [string]$FlutterHome = 'D:\ProgramData\flutter',
    [string]$JdkHome,
    [string]$AndroidHome,
    [switch]$Split,
    [switch]$AppBundle,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

function Find-Jdk {
    $user = $env:USERNAME
    $candidates = @(
        $env:JAVA_HOME,
        "C:\Users\$user\.jdks\tmp17\jdk-17.0.2",
        "C:\Users\$user\.jdks\jdk-17.0.2",
        "C:\Program Files\Java\jdk-17"
    )
    # 兜底：扫描 .jdks 下所有 jdk-17*
    $jdksRoot = "C:\Users\$user\.jdks"
    if (Test-Path $jdksRoot) {
        Get-ChildItem $jdksRoot -Directory -Filter 'jdk-17*' -ErrorAction SilentlyContinue |
            ForEach-Object { $candidates += $_.FullName }
    }

    foreach ($c in ($candidates | Where-Object { $_ })) {
        # 必须是完整 JDK：既有 javac，也有 lib\jvm.cfg
        if ((Test-Path (Join-Path $c 'bin\javac.exe')) -and
            (Test-Path (Join-Path $c 'lib\jvm.cfg'))) {
            return $c
        }
    }
    return $null
}

if (-not $JdkHome) { $JdkHome = Find-Jdk }
if (-not $JdkHome) { throw '找不到完整 JDK 17（需要 javac 与 lib\jvm.cfg）' }
if (-not $AndroidHome) {
    $AndroidHome = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "C:\Users\$env:USERNAME\AppData\Local\Android\Sdk" }
}

$env:JAVA_HOME = $JdkHome
$env:ANDROID_HOME = $AndroidHome
$env:ANDROID_SDK_ROOT = $AndroidHome
$env:PATH = "$JdkHome\bin;$FlutterHome\bin;$env:PATH"

# 国内镜像：缺这两行会导致引擎产物下载被重置
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'

Write-Host "JAVA_HOME        : $JdkHome" -ForegroundColor Cyan
Write-Host "FLUTTER_HOME     : $FlutterHome" -ForegroundColor Cyan
Write-Host "ANDROID_HOME     : $AndroidHome" -ForegroundColor Cyan
Write-Host "STORAGE_BASE_URL : $env:FLUTTER_STORAGE_BASE_URL" -ForegroundColor Cyan

$flutter = Join-Path $FlutterHome 'bin\flutter.bat'
Push-Location $repoRoot
try {
    if ($Clean) {
        Write-Host '=== flutter clean ===' -ForegroundColor Yellow
        & $flutter clean
    }

    Write-Host '=== flutter pub get ===' -ForegroundColor Yellow
    & $flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'pub get 失败' }

    if ($AppBundle) {
        Write-Host '=== flutter build appbundle ===' -ForegroundColor Yellow
        & $flutter build appbundle --release
        $out = Join-Path $repoRoot 'build\app\outputs\bundle\release\app-release.aab'
    }
    elseif ($Split) {
        Write-Host '=== flutter build apk --split-per-abi ===' -ForegroundColor Yellow
        & $flutter build apk --release --split-per-abi
        $out = Join-Path $repoRoot 'build\app\outputs\flutter-apk'
    }
    else {
        Write-Host '=== flutter build apk --release ===' -ForegroundColor Yellow
        & $flutter build apk --release
        $out = Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-release.apk'
    }

    if ($LASTEXITCODE -ne 0) { throw '构建失败' }

    Write-Host ''
    if (Test-Path $out -PathType Container) {
        Get-ChildItem $out -Filter '*.apk' | ForEach-Object {
            $mb = [math]::Round($_.Length / 1MB, 2)
            Write-Host "产物: $($_.FullName)  ($mb MB)" -ForegroundColor Green
        }
    }
    elseif (Test-Path $out) {
        $mb = [math]::Round((Get-Item $out).Length / 1MB, 2)
        Write-Host "产物: $out  ($mb MB)" -ForegroundColor Green
    }
    else {
        Write-Host "未找到预期产物：$out" -ForegroundColor Yellow
    }
}
finally {
    Pop-Location
}
