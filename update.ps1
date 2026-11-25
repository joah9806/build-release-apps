#Requires -Version 5.1
# 从 GitHub Release 下载、校验并更新 Qoder Skill；不管理项目业务文件。

[CmdletBinding()]
param(
    [ValidateSet('user', 'project')]
    [string]$Scope = 'user',

    [string]$ProjectRoot = (Get-Location).Path,

    [string]$Version = 'latest'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repository = 'joah9806/build-release-apps'
$packageName = 'build-release-apps'
$apiHeaders = @{
    'User-Agent' = 'build-release-apps-updater'
    'Accept' = 'application/vnd.github+json'
}
$downloadHeaders = @{
    'User-Agent' = 'build-release-apps-updater'
}
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("build-release-apps-" + [Guid]::NewGuid().ToString('N'))
$archive = $null

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    New-Item -ItemType Directory -Path $tempRoot | Out-Null

    $releaseUri = if ($Version -eq 'latest') {
        "https://api.github.com/repos/$repository/releases/latest"
    }
    else {
        "https://api.github.com/repos/$repository/releases/tags/$Version"
    }

    $release = Invoke-RestMethod -Uri $releaseUri -Headers $apiHeaders
    $tag = [string]$release.tag_name
    $packageVersion = $tag.TrimStart('v')

    if ($packageVersion -notmatch '^\d+\.\d+\.\d+$') {
        throw "Release tag is not a stable semantic version: $tag"
    }

    $assetName = "$packageName-$packageVersion.zip"
    $assets = @($release.assets | Where-Object { $_.name -eq $assetName })

    if ($assets.Count -ne 1) {
        throw "Expected one release asset named $assetName, found $($assets.Count)."
    }

    $asset = $assets[0]
    if ($asset.state -ne 'uploaded') {
        throw "Release asset is not ready: $assetName"
    }
    if ([string]::IsNullOrWhiteSpace([string]$asset.digest)) {
        throw "Release asset has no SHA-256 digest: $assetName"
    }

    $zipPath = Join-Path $tempRoot $assetName
    Invoke-WebRequest -Uri $asset.browser_download_url -Headers $downloadHeaders -OutFile $zipPath -UseBasicParsing

    $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = ([string]$asset.digest -replace '^sha256:', '').ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "SHA-256 verification failed for $assetName"
    }
    if ((Get-Item -LiteralPath $zipPath).Length -ne [long]$asset.size) {
        throw "Downloaded asset size does not match GitHub metadata: $assetName"
    }

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    $entry = $archive.GetEntry("skills/$packageName/SKILL.md")

    if ($null -eq $entry) {
        throw "Release asset is missing skills/$packageName/SKILL.md"
    }
    if ($entry.Length -gt 2MB) {
        throw "Skill file exceeds the 2 MB safety limit"
    }

    $reader = [System.IO.StreamReader]::new($entry.Open(), [System.Text.UTF8Encoding]::new($false))
    try {
        $skillText = $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }

    $frontmatter = [regex]::Match($skillText, '(?s)\A---\r?\n(.*?)\r?\n---(?:\r?\n|$)')
    if (-not $frontmatter.Success) {
        throw 'Downloaded SKILL.md has invalid frontmatter'
    }
    if ($frontmatter.Groups[1].Value -notmatch '(?m)^name:\s*build-release-apps\s*$') {
        throw 'Downloaded SKILL.md has an unexpected skill name'
    }

    $stagedPath = Join-Path $tempRoot 'SKILL.md'
    [System.IO.File]::WriteAllText($stagedPath, $skillText, [System.Text.UTF8Encoding]::new($false))
    $archive.Dispose()
    $archive = $null

    if ($Scope -eq 'user') {
        $targetDirectory = Join-Path $HOME '.qoder-cn\skills\build-release-apps'
    }
    else {
        $resolvedRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
        $targetDirectory = Join-Path $resolvedRoot '.qoder\skills\build-release-apps'
    }

    New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
    $installedPath = Join-Path $targetDirectory 'SKILL.md'
    $pendingPath = Join-Path $targetDirectory ('.SKILL.md-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    Copy-Item -LiteralPath $stagedPath -Destination $pendingPath

    $backupPath = $null
    if (Test-Path -LiteralPath $installedPath) {
        $backupPath = Join-Path $targetDirectory ('SKILL.md.bak-' + [DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff'))
        Move-Item -LiteralPath $installedPath -Destination $backupPath
    }

    try {
        Move-Item -LiteralPath $pendingPath -Destination $installedPath
    }
    catch {
        if ($null -ne $backupPath -and (Test-Path -LiteralPath $backupPath)) {
            Move-Item -LiteralPath $backupPath -Destination $installedPath -Force
        }
        throw
    }

    if ($null -ne $backupPath) {
        Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Updated build-release-apps to $tag"
    Write-Host "Installed to: $installedPath"
    Write-Host "Release: $($release.html_url)"
    Write-Host 'Restart Qoder or start a new session to load the update.'
}
finally {
    if ($null -ne $archive) {
        $archive.Dispose()
    }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
