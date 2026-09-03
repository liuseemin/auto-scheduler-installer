# 📦 Auto Scheduler Installation

This public repository provides a Windows installation script for `auto-scheduler`. The installer downloads the project from GitHub, configures a dedicated SSH Deploy Key, installs `uv`, synchronizes the Python environment, and creates a desktop shortcut.

## 🚀 Installation

Copy and paste the entire command below into **PowerShell** and run it:

```powershell
$installer = Join-Path $env:TEMP ("qbank-install-" + [guid]::NewGuid().ToString("N") + ".ps1")
$installerUrl = "https://raw.githubusercontent.com/liuseemin/auto-scheduler-installer/main/install.ps1?v=" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
Invoke-WebRequest $installerUrl -UseBasicParsing -OutFile $installer
powershell -ExecutionPolicy Bypass -File $installer
Remove-Item $installer -Force
```

This command downloads the latest `install.ps1` to `%TEMP%`, runs it, and deletes the temporary file after the installation is complete. The `-ExecutionPolicy Bypass` option applies only to this PowerShell process.

If no installation path is specified, the default installation directory is:

```text
%USERPROFILE%\auto-scheduler
```

During the first installation, the script will display an SSH public key. Add this key to the GitHub project's **Settings > Deploy keys > Add deploy key**.

Only read access is required. Do **not** enable **Allow write access**.

After adding the Deploy Key, return to PowerShell and press Enter. The installer will verify repository access and continue the installation.

## ✅ After Installation

A desktop shortcut named `CR自動排班.lnk` will be created.

When launched using the shortcut, the application will perform the following steps:

1. Pull the latest code from the `main` branch
2. Run `uv sync` to synchronize the Python environment
3. Run `uv run main.py`

## 📋 Requirements

* Windows
* PowerShell
* Internet access to GitHub
* Permission to add a Deploy Key to the target GitHub repository

If Git is not installed, the script will attempt to install Git for Windows using `winget`.

If `winget` is unavailable, please install Git for Windows manually before running the installer.

For `uv`, the installer will use an existing installation if available. Otherwise, it will attempt to install `uv` using `winget` or the official installer.

## 🛠️ Built With

This project uses the following core technologies and tools:

* [Google OR-Tools](https://developers.google.com/optimization?hl=en) - Used to solve scheduling optimization problems

## 🔐 Access

The source code of this automated scheduling system contains private configuration and is only available to authorized users who have been granted access through SSH authentication.

To request installation access, please contact the project administrator, [liuseemin](https://github.com/liuseemin).

## ⚙️ Custom Installation Path or Branch

After downloading the installation script, you can also specify the installation path and branch directly:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -InstallPath "$env:USERPROFILE\auto-scheduler" -Branch main
```

To install the development version, set the branch to `dev`:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -InstallPath "$env:USERPROFILE\auto-scheduler" -Branch dev
```

The default target repository is:

```text
git@github.com:liuseemin/auto-scheduler.git
```
