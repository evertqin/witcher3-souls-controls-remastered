#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Current', 'Alt1')]
    [string]$Scheme,
    [string]$GamePath,
    [string]$DocumentsPath,
    [switch]$ApplyOnly
)

$ErrorActionPreference = 'Stop'
$interactive = -not $PSBoundParameters.ContainsKey('Scheme')
$settingsPath = Join-Path $PSScriptRoot 'launcher-settings.json'
$uiRelativePath = 'content\scripts\game\gui\main_menu\ingamemenu\igmUtilities.ws'

function Test-GamePath([string]$Path) {
    if (-not $Path) { return $false }
    return ((Test-Path -LiteralPath (Join-Path $Path 'bin\x64_dx12\witcher3.exe')) -or
        (Test-Path -LiteralPath (Join-Path $Path 'bin\x64\witcher3.exe')))
}

function Find-GamePath {
    $steamPaths = @()
    foreach ($registryPath in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        $registry = Get-ItemProperty -LiteralPath $registryPath -ErrorAction SilentlyContinue
        if ($registry.SteamPath) { $steamPaths += $registry.SteamPath }
        if ($registry.InstallPath) { $steamPaths += $registry.InstallPath }
    }
    $steamPaths += Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Steam'
    foreach ($steamPath in ($steamPaths | Select-Object -Unique)) {
        $libraries = @($steamPath)
        $libraryFile = Join-Path $steamPath 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $libraryFile) {
            $libraryText = [IO.File]::ReadAllText($libraryFile)
            foreach ($match in [regex]::Matches($libraryText, '"path"\s+"([^"]+)"')) {
                $libraries += $match.Groups[1].Value.Replace('\\', '\')
            }
        }
        foreach ($library in ($libraries | Select-Object -Unique)) {
            $manifest = Join-Path $library 'steamapps\appmanifest_292030.acf'
            if (-not (Test-Path -LiteralPath $manifest)) { continue }
            $match = [regex]::Match([IO.File]::ReadAllText($manifest), '"installdir"\s+"([^"]+)"')
            if (-not $match.Success) { continue }
            $candidate = Join-Path (Join-Path $library 'steamapps\common') $match.Groups[1].Value
            if (Test-GamePath $candidate) { return $candidate }
        }
    }
    return $null
}

function Assert-GameClosed {
    if (Get-Process -Name 'witcher3' -ErrorAction SilentlyContinue) {
        throw 'Close The Witcher 3 completely before selecting a scheme. Neither file has been changed.'
    }
}

try {
    Assert-GameClosed
    $savedSettings = $null
    if (Test-Path -LiteralPath $settingsPath) {
        try { $savedSettings = [IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json }
        catch { Write-Warning 'Could not read the saved launcher preferences; using defaults.' }
    }

    if (-not $GamePath -and $savedSettings.GamePath -and (Test-GamePath $savedSettings.GamePath)) {
        $GamePath = $savedSettings.GamePath
    }
    if (-not $GamePath) { $GamePath = Find-GamePath }
    if (-not $GamePath -and $interactive) {
        Write-Host 'In Steam, choose The Witcher 3 > Manage > Browse local files.'
        $GamePath = (Read-Host 'Paste that game folder path').Trim().Trim('"')
    }
    if (-not (Test-GamePath $GamePath)) {
        throw 'Game installation not found. Run with -GamePath pointing to the folder containing bin and content.'
    }
    $GamePath = (Resolve-Path -LiteralPath $GamePath).ProviderPath

    if (-not $DocumentsPath) {
        $personalPath = [Environment]::GetFolderPath('MyDocuments')
        if (-not $personalPath) { throw 'Windows Documents folder not found. Specify -DocumentsPath explicitly.' }
        $DocumentsPath = Join-Path $personalPath 'The Witcher 3'
    }
    $DocumentsPath = [IO.Path]::GetFullPath($DocumentsPath)

    if (-not $Scheme) {
        $defaultScheme = 'Current'
        if ($savedSettings.Scheme -in @('Current', 'Alt1')) { $defaultScheme = $savedSettings.Scheme }
        Write-Host ''
        Write-Host 'The Witcher 3 - choose controls before starting' -ForegroundColor Cyan
        Write-Host '1. Current: A for canter/gallop; L3 for mounted interactions.'
        Write-Host '2. Alt1:    L3 for canter/gallop; A for mounted interactions.'
        Write-Host '0. Cancel'
        Write-Host 'Native riding gestures: hold for canter; double-press and hold for gallop.'
        Write-Host 'Each choice also installs its matching Settings > Controls diagram.'
        do {
            $choice = Read-Host "Choose 1 or 2 (Enter keeps $defaultScheme)"
            switch ($choice.Trim()) {
                '1' { $Scheme = 'Current' }
                '2' { $Scheme = 'Alt1' }
                '0' { exit 0 }
                '' { $Scheme = $defaultScheme }
                default { Write-Host 'Enter 1, 2, or 0.' }
            }
        } while (-not $Scheme)
    }

    $compatibilityPath = Join-Path $PSScriptRoot 'control-schemes\compatibility.json'
    $compatibility = [IO.File]::ReadAllText($compatibilityPath) | ConvertFrom-Json
    $nativeInputPath = Join-Path $GamePath 'bin\config\r4game\legacy\base\input_qwerty.ini'
    $nativeUiPath = Join-Path $GamePath ('content\content0\scripts\game\gui\main_menu\ingamemenu\igmUtilities.ws')
    $versionPattern = '(?ms)^\[InputSettings\]\s*\r?\nVersion=(\d+)\s*(?:\r?\n|$)'
    $nativeVersion = [regex]::Match([IO.File]::ReadAllText($nativeInputPath), $versionPattern)
    if (-not $nativeVersion.Success -or [int]$nativeVersion.Groups[1].Value -ne $compatibility.InputVersion) {
        throw 'This game uses a different input format. Update this controls package before applying it.'
    }
    if ((Get-FileHash -LiteralPath $nativeUiPath -Algorithm SHA256).Hash -ne $compatibility.VanillaUiSha256) {
        throw 'The game controller UI script differs from the supported build. Update or merge this package before applying it.'
    }

    $profile = $compatibility.Profiles.$Scheme
    $profilePath = Join-Path $PSScriptRoot ('control-schemes\' + $Scheme)
    $sourceInput = Join-Path $profilePath 'input.settings'
    $sourceUi = Join-Path (Join-Path $profilePath 'modDarkSoulsControllerScheme') $uiRelativePath
    foreach ($source in @(@{ Path = $sourceInput; Hash = $profile.InputSha256 }, @{ Path = $sourceUi; Hash = $profile.UiSha256 })) {
        if ((Get-FileHash -LiteralPath $source.Path -Algorithm SHA256).Hash -ne $source.Hash) {
            throw 'A scheme file is missing or has changed. Extract an intact copy of the package.'
        }
    }
    $sourceVersion = [regex]::Match([IO.File]::ReadAllText($sourceInput), $versionPattern)
    if (-not $sourceVersion.Success -or [int]$sourceVersion.Groups[1].Value -ne $compatibility.InputVersion) {
        throw 'Selected scheme has an incompatible input format.'
    }

    $destinationInput = Join-Path $DocumentsPath 'input.settings'
    $destinationUi = Join-Path (Join-Path $GamePath 'mods\modDarkSoulsControllerScheme') $uiRelativePath
    $transactionId = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $backupPath = Join-Path $DocumentsPath ('control-scheme-backups\' + $transactionId)
    $entries = @(
        @{ Source = $sourceInput; Destination = $destinationInput; Backup = (Join-Path $backupPath 'input.settings'); Hash = $profile.InputSha256 },
        @{ Source = $sourceUi; Destination = $destinationUi; Backup = (Join-Path $backupPath 'igmUtilities.ws'); Hash = $profile.UiSha256 }
    )
    foreach ($entry in $entries) {
        $entry.Existed = Test-Path -LiteralPath $entry.Destination
        if ($entry.Existed -and ((Get-Item -LiteralPath $entry.Destination).Attributes -band [IO.FileAttributes]::ReadOnly)) {
            throw "Destination is read-only: $($entry.Destination). Remove that attribute before switching."
        }
    }

    $applied = @()
    try {
        [void][IO.Directory]::CreateDirectory($backupPath)
        foreach ($entry in $entries) {
            if ($entry.Existed) { Copy-Item -LiteralPath $entry.Destination -Destination $entry.Backup }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($entry.Destination))
            $entry.Staged = $entry.Destination + '.scheme-' + $transactionId + '.tmp'
            Copy-Item -LiteralPath $entry.Source -Destination $entry.Staged
            if ((Get-FileHash -LiteralPath $entry.Staged -Algorithm SHA256).Hash -ne $entry.Hash) {
                throw 'Could not stage the selected scheme correctly.'
            }
        }
        Assert-GameClosed
        foreach ($entry in $entries) {
            if ($entry.Existed) { [IO.File]::Replace($entry.Staged, $entry.Destination, [NullString]::Value) }
            else { [IO.File]::Move($entry.Staged, $entry.Destination) }
            $applied += $entry
            if ((Get-FileHash -LiteralPath $entry.Destination -Algorithm SHA256).Hash -ne $entry.Hash) {
                throw 'Installed scheme failed verification.'
            }
        }
    }
    catch {
        $originalFailure = $_
        foreach ($entry in $applied) {
            try {
                if ($entry.Existed) { Copy-Item -LiteralPath $entry.Backup -Destination $entry.Destination -Force }
                elseif (Test-Path -LiteralPath $entry.Destination) { Remove-Item -LiteralPath $entry.Destination }
            }
            catch { Write-Warning "Rollback failed for $($entry.Destination). Restore its backup from $backupPath." }
        }
        throw $originalFailure
    }
    finally {
        foreach ($entry in $entries) {
            if ($entry.Staged -and (Test-Path -LiteralPath $entry.Staged)) { Remove-Item -LiteralPath $entry.Staged }
        }
    }

    try {
        @{ Scheme = $Scheme; GamePath = $GamePath } | ConvertTo-Json | Set-Content -LiteralPath $settingsPath -Encoding UTF8
    }
    catch { Write-Warning 'Scheme applied, but launcher preferences could not be saved.' }
    Write-Host "Applied $Scheme bindings and matching controller diagram." -ForegroundColor Green
    Write-Host "Previous active files backed up to: $backupPath"
    if (-not $ApplyOnly) { Start-Process -FilePath 'steam://rungameid/292030' }
}
catch {
    Write-Host "Controls launcher: $($_.Exception.Message)" -ForegroundColor Red
    if ($interactive) { [void](Read-Host 'Press Enter to close') }
    exit 1
}
