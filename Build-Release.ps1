#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutputPath)

$ErrorActionPreference = 'Stop'
if (-not $OutputPath) { $OutputPath = Join-Path $PSScriptRoot 'dist' }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$releaseName = 'Dark_Souls_Controls_and_Controller_Diagram_Remastered-1.1.1.zip'
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'control-schemes\compatibility.json') -Raw | ConvertFrom-Json
$entries = @('README.md', 'Start-Witcher3.cmd', 'Choose-Controls.ps1', 'control-schemes/compatibility.json')
foreach ($scheme in @('Current', 'Alt1')) {
    $profile = $manifest.Profiles.$scheme
    $inputRelative = 'control-schemes/' + $scheme + '/input.settings'
    $uiRelative = 'control-schemes/' + $scheme + '/modDarkSoulsControllerScheme/content/scripts/game/gui/main_menu/ingamemenu/igmUtilities.ws'
    foreach ($payload in @(@{ Path = $inputRelative; Hash = $profile.InputSha256 }, @{ Path = $uiRelative; Hash = $profile.UiSha256 })) {
        if ((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $payload.Path)).Hash -ne $payload.Hash) {
            throw "Payload hash mismatch: $($payload.Path). Update compatibility.json after intentional profile edits."
        }
        $entries += $payload.Path
    }
}

[void][IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($OutputPath))
$archivePath = Join-Path ([IO.Path]::GetFullPath($OutputPath)) $releaseName
if (Test-Path -LiteralPath $archivePath) { throw "Release already exists: $archivePath" }
$archive = [IO.Compression.ZipFile]::Open($archivePath, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($relativePath in $entries) {
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $PSScriptRoot $relativePath), $relativePath, [IO.Compression.CompressionLevel]::Optimal)
    }
}
finally { $archive.Dispose() }

$archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    if ($archive.Entries.Count -ne $entries.Count) { throw 'Wrong release file count.' }
    foreach ($relativePath in $entries) {
        $entry = $archive.GetEntry($relativePath)
        if (-not $entry) { throw "Missing archive entry: $relativePath" }
        $stream = $entry.Open()
        $sha256 = [Security.Cryptography.SHA256]::Create()
        try {
            $actualHash = ([BitConverter]::ToString($sha256.ComputeHash($stream))).Replace('-', '')
            $expectedHash = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $relativePath)).Hash
            if ($actualHash -ne $expectedHash) { throw "Archive content mismatch: $relativePath" }
        }
        finally { $sha256.Dispose(); $stream.Dispose() }
    }
}
finally { $archive.Dispose() }
Write-Output "Verified release: $archivePath"
