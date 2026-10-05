#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $temporaryBase ('witcher-controls-' + [Guid]::NewGuid().ToString('N'))
if (-not [IO.Path]::GetFullPath($testRoot).StartsWith($temporaryBase, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Invalid test directory.'
}
$game = Join-Path $testRoot 'game'
$documents = Join-Path $testRoot 'documents'
$uiSuffix = 'content\scripts\game\gui\main_menu\ingamemenu\igmUtilities.ws'
$activeUi = Join-Path $game ('mods\modDarkSoulsControllerScheme\' + $uiSuffix)
$activeInput = Join-Path $documents 'input.settings'
$nativeUi = Join-Path $game ('content\content0\scripts\game\gui\main_menu\ingamemenu\igmUtilities.ws')
$nativeInput = Join-Path $game 'bin\config\r4game\legacy\base\input_qwerty.ini'
$windowsPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Assert-Test($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Invoke-Selection([string]$Selection, [switch]$CloudInput) {
    if ($CloudInput) {
        $output = & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $testRoot 'test-cloud-input.ps1') (Join-Path $testRoot 'Choose-Controls.ps1') $Selection $game $documents 2>&1
    }
    else {
        $output = & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $testRoot 'Choose-Controls.ps1') -Scheme $Selection -GamePath $game -DocumentsPath $documents -ApplyOnly 2>&1
    }
    return @{ Code = $LASTEXITCODE; Output = ($output -join "`n") }
}

function Get-ActiveHashes {
    return @((Get-FileHash -LiteralPath $activeInput).Hash, (Get-FileHash -LiteralPath $activeUi).Hash) -join ':'
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'Choose-Controls.ps1') -Destination $testRoot
    Copy-Item -LiteralPath (Join-Path $projectRoot 'control-schemes') -Destination $testRoot -Recurse
    New-Item -ItemType Directory -Path (Join-Path $game 'bin\x64_dx12'),(Split-Path $nativeInput -Parent),(Split-Path $nativeUi -Parent),$documents,(Split-Path $activeUi -Parent) -Force | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $game 'bin\x64_dx12\witcher3.exe'), [byte[]]@())
    [IO.File]::WriteAllText($nativeInput, "[InputSettings]`r`nVersion=60`r`n")

    # Obtain the compatible vanilla script through the locally stored snapshot:
    # reversing the original label permutation recovers the untouched source.
    $savedUi = Join-Path $PSScriptRoot 'fixtures\igmUtilities-1.0.0.ws'
    $bytes = [IO.File]::ReadAllBytes($savedUi)
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    $inverse = @{ txtRightBumper = 'txtXButton'; txtRightTrigger = 'txtYButton'; txtXButton = 'txtRightTrigger'; txtLeftTrigger = 'txtRightBumper'; txtLeftBumper = 'txtLeftTrigger'; txtYButton = 'txtLeftBumper' }
    $start = $text.IndexOf('function InGameMenu_CreateControllerData(')
    $pattern = '(SetMemberFlashString\(")(txtXButton|txtYButton|txtRightTrigger|txtRightBumper|txtLeftTrigger|txtLeftBumper)(")'
    $body = [regex]::Replace($text.Substring($start), $pattern, { param($match) $match.Groups[1].Value + $inverse[$match.Groups[2].Value] + $match.Groups[3].Value })
    [IO.File]::WriteAllBytes($nativeUi, [Text.Encoding]::UTF8.GetBytes($text.Substring(0, $start) + $body))
    $manifest = Get-Content -LiteralPath (Join-Path $projectRoot 'control-schemes\compatibility.json') -Raw | ConvertFrom-Json
    Assert-Test ((Get-FileHash -LiteralPath $nativeUi).Hash -eq $manifest.VanillaUiSha256) 'Vanilla fixture must match supported script exactly.'
    [IO.File]::WriteAllText($activeInput, 'original input marker')
    [IO.File]::WriteAllText($activeUi, 'original UI marker')
    # Supply cloud metadata without needing OneDrive on the test machine.
    @'
param($Launcher, $Selection, $Game, $Documents)
$cloudInputPath = Join-Path $Documents 'input.settings'
function Get-Item {
    param($LiteralPath)
    $item = Microsoft.PowerShell.Management\Get-Item -LiteralPath $LiteralPath
    if ($LiteralPath -eq $cloudInputPath) {
        return [pscustomobject]@{ Attributes = ($item.Attributes -bor [IO.FileAttributes]::ReparsePoint) }
    }
    return $item
}
& $Launcher -Scheme $Selection -GamePath $Game -DocumentsPath $Documents -ApplyOnly
exit $LASTEXITCODE
'@ | Set-Content -LiteralPath (Join-Path $testRoot 'test-cloud-input.ps1') -Encoding UTF8

    $first = Invoke-Selection 'Alt1'
    Assert-Test ($first.Code -eq 0) $first.Output
    Assert-Test ((Get-FileHash -LiteralPath $activeInput).Hash -eq $manifest.Profiles.Alt1.InputSha256) 'Alt1 input mismatch.'
    Assert-Test ((Get-FileHash -LiteralPath $activeUi).Hash -eq $manifest.Profiles.Alt1.UiSha256) 'Alt1 diagram mismatch.'
    $backup = Get-ChildItem -LiteralPath (Join-Path $documents 'control-scheme-backups') -Directory | Select-Object -First 1
    Assert-Test ([IO.File]::ReadAllText((Join-Path $backup.FullName 'input.settings')) -eq 'original input marker') 'Original binding backup missing.'
    Assert-Test ([IO.File]::ReadAllText((Join-Path $backup.FullName 'igmUtilities.ws')) -eq 'original UI marker') 'Original UI backup missing.'

    $second = Invoke-Selection 'Current'
    Assert-Test ($second.Code -eq 0) $second.Output
    Assert-Test ((Get-FileHash -LiteralPath $activeInput).Hash -eq $manifest.Profiles.Current.InputSha256) 'Current input mismatch.'
    Assert-Test ((Get-FileHash -LiteralPath $activeUi).Hash -eq $manifest.Profiles.Current.UiSha256) 'Current diagram mismatch.'

    # A writable file with no delete permission must still support switching.
    $inputAcl = Get-Acl -LiteralPath $activeInput
    $parentAcl = Get-Acl -LiteralPath $documents
    $restrictedInputAcl = Get-Acl -LiteralPath $activeInput
    $restrictedParentAcl = Get-Acl -LiteralPath $documents
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $restrictedInputAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($identity, [Security.AccessControl.FileSystemRights]::Delete, [Security.AccessControl.AccessControlType]::Deny))
    $restrictedParentAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($identity, [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles, [Security.AccessControl.AccessControlType]::Deny))
    $candidate = Join-Path $documents 'replace-probe.tmp'
    try {
        Set-Acl -LiteralPath $documents -AclObject $restrictedParentAcl
        Set-Acl -LiteralPath $activeInput -AclObject $restrictedInputAcl
        Copy-Item -LiteralPath $activeInput -Destination $candidate
        $replaceRefused = $false
        try { [IO.File]::Replace($candidate, $activeInput, [NullString]::Value) }
        catch { $replaceRefused = $true }
        Assert-Test $replaceRefused 'Fixture must reproduce a file-replacement failure.'
        $noDelete = Invoke-Selection 'Alt1'
        Assert-Test ($noDelete.Code -eq 0) $noDelete.Output
        Assert-Test ((Get-FileHash -LiteralPath $activeInput).Hash -eq $manifest.Profiles.Alt1.InputSha256) 'Write-only fallback input mismatch.'
        Assert-Test ((Get-FileHash -LiteralPath $activeUi).Hash -eq $manifest.Profiles.Alt1.UiSha256) 'Write-only fallback diagram mismatch.'
        Assert-Test ((Get-Acl -LiteralPath $activeInput).Sddl -eq $restrictedInputAcl.Sddl) 'Overwrite changed destination permissions.'
    }
    finally {
        Set-Acl -LiteralPath $activeInput -AclObject $inputAcl
        Set-Acl -LiteralPath $documents -AclObject $parentAcl
        if (Test-Path -LiteralPath $candidate) { Remove-Item -LiteralPath $candidate }
    }

    [IO.File]::AppendAllText($activeInput, 'old trailing content must be truncated')
    $cloud = Invoke-Selection 'Current' -CloudInput
    Assert-Test ($cloud.Code -eq 0) $cloud.Output
    Assert-Test ((Get-FileHash -LiteralPath $activeInput).Hash -eq $manifest.Profiles.Current.InputSha256) 'Cloud overwrite did not truncate old input correctly.'
    Assert-Test ((Get-FileHash -LiteralPath $activeUi).Hash -eq $manifest.Profiles.Current.UiSha256) 'Cloud overwrite diagram mismatch.'
    $beforeFailure = Get-ActiveHashes

    # Make the second replacement fail after the first succeeds. The launcher
    # must restore the old bindings and leave the original diagram intact.
    $lock = [IO.File]::Open($activeUi, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $failed = Invoke-Selection 'Alt1' -CloudInput
        Assert-Test ($failed.Code -eq 1) 'Locked diagram should reject a partial switch.'
        Assert-Test ($failed.Output.Contains($activeUi)) 'Failure should identify the destination path.'
    }
    finally { $lock.Dispose() }
    Assert-Test ((Get-ActiveHashes) -eq $beforeFailure) 'Partial switch did not restore both active files.'
    Assert-Test (@(Get-ChildItem -LiteralPath $documents -Filter '*.tmp').Count -eq 0) 'Input staging files left over.'
    Assert-Test (@(Get-ChildItem -LiteralPath (Split-Path $activeUi -Parent) -Filter '*.tmp').Count -eq 0) 'UI staging files left over.'

    $lock = [IO.File]::Open($activeInput, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $lockedCloud = Invoke-Selection 'Alt1' -CloudInput
        Assert-Test ($lockedCloud.Code -eq 1) 'Locked cloud input should reject overwrite.'
        Assert-Test ($lockedCloud.Output.Contains($activeInput)) 'Cloud failure should identify the destination path.'
    }
    finally { $lock.Dispose() }
    Assert-Test ((Get-ActiveHashes) -eq $beforeFailure) 'Locked cloud input changed active files.'

    [IO.File]::WriteAllText($nativeInput, "[InputSettings]`r`nVersion=61`r`n")
    $wrongVersion = Invoke-Selection 'Alt1'
    Assert-Test ($wrongVersion.Code -eq 1) 'Incompatible input version should be refused.'
    Assert-Test ((Get-ActiveHashes) -eq $beforeFailure) 'Version refusal changed active files.'
    [IO.File]::WriteAllText($nativeInput, "[InputSettings]`r`nVersion=60`r`n")

    $nativeBytes = [IO.File]::ReadAllBytes($nativeUi)
    [IO.File]::AppendAllText($nativeUi, 'updated game UI')
    $wrongUi = Invoke-Selection 'Alt1'
    Assert-Test ($wrongUi.Code -eq 1) 'An updated game UI script should be refused.'
    Assert-Test ((Get-ActiveHashes) -eq $beforeFailure) 'UI incompatibility changed active files.'
    [IO.File]::WriteAllBytes($nativeUi, $nativeBytes)

    $altInput = Join-Path $testRoot 'control-schemes\Alt1\input.settings'
    Add-Content -LiteralPath $altInput -Value 'unexpected modification'
    $corruptProfile = Invoke-Selection 'Alt1'
    Assert-Test ($corruptProfile.Code -eq 1) 'Changed profile should be refused.'
    Assert-Test ((Get-ActiveHashes) -eq $beforeFailure) 'Profile refusal changed active files.'

    $guardHarness = Join-Path $testRoot 'test-running-guard.ps1'
    @'
param($Launcher, $Game, $Documents)
function Get-Process { param($Name, $ErrorAction) return [pscustomobject]@{ ProcessName = 'witcher3' } }
& $Launcher -Scheme Alt1 -GamePath $Game -DocumentsPath $Documents -ApplyOnly
exit $LASTEXITCODE
'@ | Set-Content -LiteralPath $guardHarness -Encoding UTF8
    $guardOutput = & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $guardHarness (Join-Path $testRoot 'Choose-Controls.ps1') $game $documents 2>&1
    Assert-Test ($LASTEXITCODE -eq 1) 'Running-game guard should refuse.'
    Assert-Test (($guardOutput -join '') -match 'Close The Witcher 3 completely') 'Wrong running-game rejection.'
    Assert-Test ((Get-ActiveHashes) -eq $beforeFailure) 'Running-game guard changed active files.'

    Write-Output 'PASS: Windows PowerShell 5.1 applied both schemes with matching diagrams and exact backups.'
    Write-Output 'PASS: Reproduced replacement failure with denied delete permission; overwrite fallback and cloud-file truncation succeeded.'
    Write-Output 'PASS: A locked diagram rolled back the partial switch; staged files were cleaned.'
    Write-Output 'PASS: Different input format, changed game UI, changed payload, and running game refused without changes.'
}
finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    if ($resolvedTestRoot.StartsWith($temporaryBase, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolvedTestRoot -Leaf) -match '^witcher-controls-[a-f0-9]{32}$') {
        if (Test-Path -LiteralPath $resolvedTestRoot) { Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force }
    }
    else { throw 'Refusing to clean an unverified test path.' }
}
