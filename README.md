<!-- create link to README_EN.md -->
[English](README_EN.md)

# 📦 自動化排班程式安裝

這個公開 repository 提供 `auto-scheduler` 的 Windows 安裝腳本。安裝腳本會從 GitHub 下載專案、設定專用 SSH Deploy Key、安裝 `uv`、同步 Python 環境，並在桌面建立啟動捷徑。

## 🚀 安裝

請在 **PowerShell** 中複製貼上以下整段指令並執行：

```powershell
$installer = Join-Path $env:TEMP ("qbank-install-" + [guid]::NewGuid().ToString("N") + ".ps1")
$installerUrl = "https://raw.githubusercontent.com/liuseemin/auto-scheduler-installer/main/install.ps1?v=" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
Invoke-WebRequest $installerUrl -UseBasicParsing -OutFile $installer
powershell -ExecutionPolicy Bypass -File $installer
Remove-Item $installer -Force
```

指令會將最新版 `install.ps1` 暫存到 `%TEMP%`，執行完成後刪除暫存檔。`-ExecutionPolicy Bypass` 僅套用於這次啟動的 PowerShell 程序。

安裝過程中若未指定路徑，預設會安裝到：

```text
%USERPROFILE%\auto-scheduler
```

腳本會在第一次使用時顯示公鑰，請將它加入 GitHub 專案的 **Settings > Deploy keys > Add deploy key**。只需啟用讀取權限，不要啟用 **Allow write access**。加入後回到 PowerShell 按 Enter，腳本會驗證存取權限並繼續安裝。

## ✅ 安裝完成後

桌面上會建立 `CR自動排班.lnk` 捷徑。使用捷徑啟動時，程式會依序：

1. 從 `main` 分支取得最新程式碼
2. 執行 `uv sync` 同步 Python 環境
3. 執行 `uv run main.py`

## 📋 需求

- Windows
- PowerShell
- 可連線至 GitHub 的網路
- 能將 Deploy Key 加入目標 GitHub repository 的權限

若系統尚未安裝 Git，腳本會嘗試使用 `winget` 安裝 Git for Windows；若沒有 `winget`，請先手動安裝 Git for Windows。`uv` 則會優先使用既有版本，否則嘗試透過 `winget` 或官方安裝程式安裝。

## 🛠️ 使用技術 (Built With)

本專案使用以下核心技術與工具：
* [Google OR-Tools](https://developers.google.com/optimization?hl=zh-tw) - 解決排班最佳化問題

## 🔐 權限

此自動化排班系統之原始碼含有 Private configuration，只公開給授權者進行SSH驗證得以安裝。

若想要取得安裝權限，請聯繫開發管理者 [liuseemin](https://github.com/liuseemin)

## ⚙️ 自訂安裝路徑或分支

下載腳本後，也可以直接傳入參數：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -InstallPath "$env:USERPROFILE\auto-scheduler" -Branch main
```

如果想要取得開發版本，請設定Branch為`dev`：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -InstallPath "$env:USERPROFILE\auto-scheduler" -Branch dev
```

預設目標 repository 為：

```text
git@github.com:liuseemin/auto-scheduler.git
```
