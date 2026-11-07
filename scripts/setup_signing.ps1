# 生成 Android release 签名（keystore + key.properties）
#
# 用法（在仓库根目录执行）：
#   pwsh -File scripts/setup_signing.ps1
#   pwsh -File scripts/setup_signing.ps1 -StorePassword 'your-strong-password'
#
# 说明：
#   - 生成的 release-keystore.jks 与 android/key.properties 都已被 .gitignore 排除。
#   - 若两者已存在，脚本默认跳过，不会覆盖既有签名（覆盖会导致已发布应用无法升级）。
#   - CI 中可改用环境变量注入口令，无需把口令写入文件。

param(
    [string]$StorePassword,
    [string]$KeyAlias = 'kml_explorer_key',
    [string]$DName = 'CN=KML Explorer, OU=Dev, O=KML Explorer, L=Shenzhen, ST=Guangdong, C=CN',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$androidDir = Join-Path $repoRoot 'android'
$keystorePath = Join-Path $androidDir 'app\release-keystore.jks'
$propertiesPath = Join-Path $androidDir 'key.properties'

if ((Test-Path $keystorePath) -and -not $Force) {
    Write-Host "已存在签名文件：$keystorePath" -ForegroundColor Yellow
    Write-Host "跳过生成。若确实要重新生成，请加 -Force（会导致已发布应用无法增量升级）。"
    exit 0
}

# 定位 keytool：优先 JAVA_HOME，其次 PATH
$keytool = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin\keytool.exe' } else { 'keytool' }
if ($env:JAVA_HOME -and -not (Test-Path $keytool)) {
    Write-Host "JAVA_HOME 下找不到 keytool：$keytool" -ForegroundColor Red
    exit 1
}

if (-not $StorePassword) {
    # 生成 28 位随机口令（仅字母数字，避免 shell/编码问题）
    $chars = (48..57) + (65..90) + (97..122) | ForEach-Object { [char]$_ }
    $StorePassword = -join (1..28 | ForEach-Object { $chars | Get-Random })
    Write-Host '已自动生成随机签名口令。'
}

if (Test-Path $keystorePath) { Remove-Item $keystorePath -Force }

& $keytool -genkeypair -v `
    -keystore $keystorePath `
    -alias $KeyAlias `
    -keyalg RSA -keysize 2048 -validity 10000 `
    -storepass $StorePassword -keypass $StorePassword `
    -dname $DName

if ($LASTEXITCODE -ne 0) {
    Write-Host 'keytool 生成签名失败。' -ForegroundColor Red
    exit $LASTEXITCODE
}

$lines = @(
    '# 本文件包含签名口令，禁止提交到版本库。',
    '# 由 scripts/setup_signing.ps1 生成。',
    'storeFile=release-keystore.jks',
    "storePassword=$StorePassword",
    "keyAlias=$KeyAlias",
    "keyPassword=$StorePassword"
)
Set-Content -Path $propertiesPath -Value $lines -Encoding utf8

Write-Host ''
Write-Host '签名配置完成：' -ForegroundColor Green
Write-Host "  keystore : $keystorePath"
Write-Host "  props    : $propertiesPath"
Write-Host ''
Write-Host '请妥善备份该 keystore 与口令，丢失后将无法为已上架应用发布更新。' -ForegroundColor Yellow
