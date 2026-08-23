# use: powershell.exe -ExecutionPolicy Bypass -File <script> to avoid execution policy issues

[CmdletBinding()]
param(
    [string]$InstallPath,
    [string]$RepositoryUrl = "git@github.com:liuseemin/auto-scheduler.git",
    [string]$Branch = "main"
)

$ErrorActionPreference = "Stop"

function Refresh-Path {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $env:Path = "$machinePath;$userPath"
}

function Invoke-Git {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    & $script:gitCommand @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed with exit code $LASTEXITCODE."
    }
}

function Invoke-Uv {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    & $script:uvCommand @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "uv command failed with exit code $LASTEXITCODE."
    }
}

function Find-Uv {
    $uv = Get-Command uv.exe -ErrorAction SilentlyContinue

    if ($null -ne $uv) {
        $script:uvCommand = $uv.Source
        return $true
    }

    $candidate = Join-Path $HOME ".local\bin\uv.exe"

    if (Test-Path -LiteralPath $candidate) {
        $script:uvCommand = $candidate
        return $true
    }

    return $false
}

function Install-Uv {
    if (Find-Uv) {
        return
    }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue

    if ($null -ne $winget) {
        Write-Host "Installing uv with winget..."

        & $winget.Source install `
            --id astral-sh.uv `
            --exact `
            --scope user `
            --accept-package-agreements `
            --accept-source-agreements `
            --source winget

        if ($LASTEXITCODE -eq 0) {
            Refresh-Path

            if (Find-Uv) {
                return
            }
        }
    }

    Write-Host "Installing uv with the official installer..."

    $uvInstaller = Join-Path $env:TEMP "uv-install.ps1"

    Invoke-WebRequest `
        -Uri "https://astral.sh/uv/install.ps1" `
        -OutFile $uvInstaller `
        -UseBasicParsing

    & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $uvInstaller

    $installerExitCode = $LASTEXITCODE

    Remove-Item `
        -LiteralPath $uvInstaller `
        -Force `
        -ErrorAction SilentlyContinue

    if ($installerExitCode -ne 0) {
        throw "uv installation failed with exit code $installerExitCode."
    }

    Refresh-Path

    if (-not (Find-Uv)) {
        throw "uv was installed but could not be found. Open a new PowerShell window and run this script again."
    }
}

function Find-SshTools {
    Write-Host "Checking for SSH client tools..."
    # First try PATH
    $ssh = Get-Command ssh.exe -ErrorAction SilentlyContinue
    $sshKeygen = Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue

    if ($null -ne $ssh -and $null -ne $sshKeygen) {
        $script:sshCommand = $ssh.Source
        $script:sshKeygenCommand = $sshKeygen.Source
        return $true
    }

    # Try Git for Windows bundled OpenSSH
    $candidateDirectories = @()

    if ($script:gitCommand) {
        $gitCmdDirectory = Split-Path -Parent $script:gitCommand

        # Example:
        # C:\Program Files\Git\cmd\git.exe
        # -> C:\Program Files\Git
        $gitRoot = Split-Path -Parent $gitCmdDirectory

        $candidateDirectories += Join-Path $gitRoot "usr\bin"
    }

    $candidateDirectories += @(
        "C:\Program Files\Git\usr\bin",
        (Join-Path $env:LOCALAPPDATA "Programs\Git\usr\bin")
    )

    foreach ($directory in $candidateDirectories) {
        if ([string]::IsNullOrWhiteSpace($directory)) {
            continue
        }

        $sshPath = Join-Path $directory "ssh.exe"
        $sshKeygenPath = Join-Path $directory "ssh-keygen.exe"

        if (
            (Test-Path -LiteralPath $sshPath) -and
            (Test-Path -LiteralPath $sshKeygenPath)
        ) {
            $script:sshCommand = $sshPath
            $script:sshKeygenCommand = $sshKeygenPath
            return $true
        }
    }

    return $false
}

function Ensure-DeployKey {
    $sshDirectory = Join-Path $HOME ".ssh"

    $privateKey = Join-Path $sshDirectory "auto-scheduler_deploy_ed25519"
    $publicKey = "$privateKey.pub"

    if (-not (Test-Path -LiteralPath $sshDirectory)) {
        New-Item `
            -ItemType Directory `
            -Path $sshDirectory `
            -Force |
        Out-Null
    }

    if (-not (Test-Path -LiteralPath $privateKey)) {
        Write-Host "Generating a dedicated SSH deploy key..."

        & $script:sshKeygenCommand `
            -t ed25519 `
            -f $privateKey `
            -N '""' `
            -C "auto-scheduler@$env:COMPUTERNAME"

        if ($LASTEXITCODE -ne 0) {
            throw "SSH deploy key generation failed."
        }
    }

    # If private key exists but .pub is missing,
    # rebuild the public key instead of overwriting the private key.
    if (-not (Test-Path -LiteralPath $publicKey)) {
        Write-Host "Recreating public key from existing private key..."

        $generatedPublicKey = & $script:sshKeygenCommand `
            -y `
            -f $privateKey

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to recreate SSH public key."
        }

        Set-Content `
            -LiteralPath $publicKey `
            -Value "$generatedPublicKey auto-scheduler@$env:COMPUTERNAME"
    }

    Write-Host "Public key: $publicKey"

    return @{
        PrivateKey = $privateKey
        PublicKey  = $publicKey
    }
}

function New-GitSshWrapper {
    param(
        [Parameter(Mandatory)]
        [string]$PrivateKey
    )

    $wrapperDir = Join-Path $env:USERPROFILE ".auto-scheduler"

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $wrapperDir |
    Out-Null

    $wrapperPath = Join-Path $wrapperDir "git-ssh.cmd"

    $content = @"
@echo off
"$script:sshCommand" -i "$PrivateKey" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new %*
"@

    Set-Content `
        -LiteralPath $wrapperPath `
        -Value $content `
        -Encoding ASCII

    return $wrapperPath
}

function Test-RepositoryAccess {
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryUrl,

        [Parameter(Mandatory)]
        [string]$PrivateKey
    )

    $sshWrapper = New-GitSshWrapper `
        -PrivateKey $PrivateKey

    $sshWrapperGitPath = $sshWrapper -replace '\\', '/'

    Write-Host "Deploy key SSH wrapper: $sshWrapperGitPath"

    $oldErrorActionPreference = $ErrorActionPreference

    try {
        # ssh may legitimately write warnings to stderr.
        # Do not let Windows PowerShell convert those into terminating errors.
        $ErrorActionPreference = "Continue"

        & $script:gitCommand `
            -c "core.sshCommand=$sshWrapperGitPath" `
            ls-remote `
            $RepositoryUrl `
            HEAD `
            2>$null

        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }

    return ($exitCode -eq 0)
}

function Initialize-RepositoryDeployKey {
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryUrl
    )

    if ($RepositoryUrl -notmatch '^git@github\.com:') {
        throw "Deploy-key mode requires an SSH GitHub URL such as git@github.com:owner/repository.git"
    }

    if (-not (Find-SshTools)) {
        throw "SSH client tools were not found. Git for Windows may be incomplete or unavailable."
    }

    $key = Ensure-DeployKey

    if (
        Test-RepositoryAccess `
            -RepositoryUrl $RepositoryUrl `
            -PrivateKey $key.PrivateKey
    ) {
        Write-Host "Deploy key already has access to the repository."
        return $key
    }

    Write-Host ""
    Write-Host "This computer does not yet have access to the private repository."
    Write-Host ""
    Write-Host "Add the following public key to:"
    Write-Host ""
    Write-Host "GitHub repository -> Settings -> Deploy keys -> Add deploy key"
    Write-Host ""
    Write-Host "Do NOT enable 'Allow write access'."
    Write-Host ""
    Write-Host "------------------------------------------------------------"
    Get-Content -LiteralPath $key.PublicKey | Write-Host
    Write-Host "------------------------------------------------------------"
    Write-Host ""

    [void](Read-Host "Press Enter after adding the deploy key to GitHub")

    if (
        -not (
            Test-RepositoryAccess `
                -RepositoryUrl $RepositoryUrl `
                -PrivateKey $key.PrivateKey
        )
    ) {
        throw "The deploy key still cannot access the repository. Confirm that the public key was added to the correct repository."
    }

    Write-Host "Deploy key verified."

    return $key
}

function Invoke-GitCloneWithDeployKey {
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryUrl,

        [Parameter(Mandatory)]
        [string]$InstallPath,

        [Parameter(Mandatory)]
        [string]$PrivateKey,

        [Parameter(Mandatory)]
        [string]$Branch
    )

    $sshWrapper = New-GitSshWrapper `
        -PrivateKey $PrivateKey

    $sshWrapperGitPath = $sshWrapper -replace '\\', '/'

    & $script:gitCommand `
        -c "core.sshCommand=$sshWrapperGitPath" `
        clone `
        --branch $Branch `
        --single-branch `
        $RepositoryUrl `
        $InstallPath

    if ($LASTEXITCODE -ne 0) {
        throw "Git clone failed with exit code $LASTEXITCODE."
    }
}

function Set-RepositoryDeployKey {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$PrivateKey
    )

    $sshWrapper = New-GitSshWrapper `
        -PrivateKey $PrivateKey

    $sshWrapperGitPath = $sshWrapper -replace '\\', '/'

    Push-Location $ProjectPath

    try {
        Invoke-Git -Arguments @(
            "config",
            "--local",
            "core.sshCommand",
            $sshWrapperGitPath
        )
    }
    finally {
        Pop-Location
    }
}

function New-AppLauncher {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$GitPath,

        [Parameter(Mandatory)]
        [string]$UvPath,

        [Parameter(Mandatory)]
        [string]$Branch
    )

    $launcherPath = Join-Path $ProjectPath "run_auto_scheduler.ps1"

    $launcherContent = @"
`$ErrorActionPreference = "Stop"

Set-Location -LiteralPath "$ProjectPath"

Write-Host "Updating auto-scheduler..."

& "$GitPath" fetch origin "$Branch"
if (`$LASTEXITCODE -ne 0) {
    Write-Host "git fetch failed."
    Read-Host "Press Enter to exit"
    exit 1
}

& "$GitPath" checkout "$Branch"
if (`$LASTEXITCODE -ne 0) {
    Write-Host "git checkout failed."
    Read-Host "Press Enter to exit"
    exit 1
}

& "$GitPath" pull --ff-only origin "$Branch"
if (`$LASTEXITCODE -ne 0) {
    Write-Host "git pull failed."
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Synchronizing Python environment..."

& "$UvPath" sync
if (`$LASTEXITCODE -ne 0) {
    Write-Host "uv sync failed."
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Starting auto-scheduler..."

& "$UvPath" run main.py
"@

    Set-Content `
        -LiteralPath $launcherPath `
        -Value $launcherContent `
        -Encoding UTF8

    return $launcherPath
}

function New-DesktopShortcut {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$LauncherPath,

        [Parameter(Mandatory)]
        [string]$UvPath
    )

    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktopPath "Auto Scheduler.lnk"

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)

    $iconPath = Join-Path $ProjectPath "icon\appicon.ico"

    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$LauncherPath`""
    $shortcut.WorkingDirectory = $ProjectPath
    $shortcut.Description = "Auto Scheduler"

    if (Test-Path -LiteralPath $iconPath) {
        $shortcut.IconLocation = "$iconPath,0"
    }
    else {
        $shortcut.IconLocation = "$UvPath,0"
    }

    $shortcut.Save()

    return $shortcutPath
}


# ============================================================
# Main
# ============================================================

if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $defaultPath = Join-Path $HOME "auto-scheduler"

    $InstallPath = Read-Host "Installation folder [$defaultPath]"

    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $InstallPath = $defaultPath
    }
}

$InstallPath = [Environment]::ExpandEnvironmentVariables(
    $InstallPath.Trim().Trim('"')
)

$InstallPath = [System.IO.Path]::GetFullPath($InstallPath)


# ------------------------------------------------------------
# Step 1: Git
# ------------------------------------------------------------

Write-Host "[1/6] Checking for Git..."

$git = Get-Command git.exe -ErrorAction SilentlyContinue

if ($null -eq $git) {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue

    if ($null -eq $winget) {
        throw "Git was not found. Install Git for Windows and run this script again."
    }

    Write-Host "Installing Git for Windows..."

    & $winget.Source install `
        --id Git.Git `
        --exact `
        --scope user `
        --accept-package-agreements `
        --accept-source-agreements `
        --source winget

    if ($LASTEXITCODE -ne 0) {
        throw "Git installation failed."
    }

    Refresh-Path

    $git = Get-Command git.exe -ErrorAction SilentlyContinue
}

if ($null -eq $git) {
    # Git may not immediately appear in PATH after winget.
    $gitCandidates = @(
        "C:\Program Files\Git\cmd\git.exe",
        (Join-Path $env:LOCALAPPDATA "Programs\Git\cmd\git.exe")
    )

    foreach ($candidate in $gitCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            $git = @{
                Source = $candidate
            }

            break
        }
    }
}

if ($null -eq $git) {
    throw "Git was installed but could not be found. Open a new PowerShell window and run this script again."
}

$script:gitCommand = $git.Source


# ------------------------------------------------------------
# Step 2: Deploy key
# ------------------------------------------------------------

Write-Host "[2/6] Configuring repository access..."

$deployKey = Initialize-RepositoryDeployKey `
    -RepositoryUrl $RepositoryUrl


# ------------------------------------------------------------
# Step 3: Clone / update
# ------------------------------------------------------------

Write-Host "[3/6] Installing project into $InstallPath..."

if (Test-Path -LiteralPath $InstallPath) {
    $items = @(
        Get-ChildItem `
            -Force `
            -LiteralPath $InstallPath
    )

    $gitFolder = Join-Path $InstallPath ".git"

    if ($items.Count -eq 0) {
        Invoke-GitCloneWithDeployKey `
            -RepositoryUrl $RepositoryUrl `
            -InstallPath $InstallPath `
            -PrivateKey $deployKey.PrivateKey
    }
    elseif (Test-Path -LiteralPath $gitFolder) {
        # Configure this repository to always use its dedicated deploy key.
        Set-RepositoryDeployKey `
            -ProjectPath $InstallPath `
            -PrivateKey $deployKey.PrivateKey

        Push-Location $InstallPath

        try {
            Invoke-Git -Arguments @(
                "fetch",
                "origin",
                $Branch
            )

            Invoke-Git -Arguments @(
                "checkout",
                $Branch
            )

            Invoke-Git -Arguments @(
                "pull",
                "--ff-only",
                "origin",
                $Branch
            )

        }
        finally {
            Pop-Location
        }
    }
    else {
        throw "Installation folder exists and is not empty: $InstallPath"
    }
}
else {
    $parent = Split-Path -Parent $InstallPath

    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item `
            -ItemType Directory `
            -Path $parent `
            -Force |
        Out-Null
    }

    Invoke-GitCloneWithDeployKey `
        -RepositoryUrl $RepositoryUrl `
        -InstallPath $InstallPath `
        -PrivateKey $deployKey.PrivateKey
}

# Persist the deploy-key SSH command inside this repository only.
Set-RepositoryDeployKey `
    -ProjectPath $InstallPath `
    -PrivateKey $deployKey.PrivateKey


# ------------------------------------------------------------
# Validate project
# ------------------------------------------------------------

$pyproject = Join-Path $InstallPath "pyproject.toml"

if (-not (Test-Path -LiteralPath $pyproject)) {
    throw "The project was downloaded, but pyproject.toml was not found."
}

Set-Location -Path $InstallPath


# ------------------------------------------------------------
# Step 4: uv
# ------------------------------------------------------------

Write-Host "[4/6] Checking for uv..."

Install-Uv


# ------------------------------------------------------------
# Step 5: uv sync
# ------------------------------------------------------------

Write-Host "[5/6] Synchronizing the uv environment..."

Invoke-Uv -Arguments @(
    "sync"
)


# ------------------------------------------------------------
# Step 6: shortcut
# ------------------------------------------------------------

Write-Host "[6/6] Creating launcher and desktop shortcut..."

$launcherPath = New-AppLauncher `
    -ProjectPath $InstallPath `
    -GitPath $script:gitCommand `
    -UvPath $script:uvCommand `
    -Branch $Branch

$shortcutPath = New-DesktopShortcut `
    -ProjectPath $InstallPath `
    -LauncherPath $launcherPath `
    -UvPath $script:uvCommand


# ------------------------------------------------------------
# Done
# ------------------------------------------------------------

Write-Host ""
Write-Host "Installation completed: $InstallPath"
Write-Host "Deploy key: $($deployKey.PrivateKey)"
Write-Host "Desktop shortcut created: $shortcutPath"
Write-Host "Shortcut runs: uv run main.py"