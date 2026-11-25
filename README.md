# build-release-apps

一个用于规范应用开发、清理、验证和版本发布的 Qoder Skill。已有应用修改跳过验证和发布确认，直接推送并发布版本；新应用、文档和 Skill 按各自流程验证后发布。本仓库同时提供独立的 GitHub 更新脚本，更新方式不写入 Skill 正文。

## 从 GitHub 更新

适用于 Windows PowerShell 5.1 及以上版本，不需要 npm 或 GitHub CLI。

### 一键更新到最新 Release

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p = Join-Path $env:TEMP 'update-build-release-apps.ps1'; Invoke-WebRequest -Uri 'https://github.com/joah9806/build-release-apps/releases/latest/download/update.ps1' -OutFile $p; & $p"
```

默认更新当前 Windows 用户的 Qoder CN Skill：

```text
%USERPROFILE%\.qoder-cn\skills\build-release-apps
```

### 下载后检查再运行

```powershell
$p = Join-Path $env:TEMP 'update-build-release-apps.ps1'
Invoke-WebRequest -Uri 'https://github.com/joah9806/build-release-apps/releases/latest/download/update.ps1' -OutFile $p
notepad $p
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p
```

### 更新指定项目

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p -Scope project -ProjectRoot "C:\path\to\repo"
```

### 更新指定版本

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p -Version v0.1.4
```

## 更新机制

- 从 GitHub Releases API 获取最新 Release 或指定标签。
- 下载对应版本压缩包并校验 GitHub 提供的 SHA-256 摘要和文件大小。
- 只读取 `skills/build-release-apps/SKILL.md`，校验名称和 frontmatter。
- 原子替换目标 `SKILL.md`，保留目录内的其他本地文件。
- 更新完成后重启 Qoder 或新建会话。
