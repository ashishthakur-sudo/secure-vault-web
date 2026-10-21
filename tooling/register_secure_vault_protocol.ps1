param(
    [string]$ExecutablePath = (Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release\secure_vault.exe')
)

$ErrorActionPreference = 'Stop'

$resolvedExecutable = (Resolve-Path -LiteralPath $ExecutablePath).Path
$protocolKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Classes\securevault')
$commandKey = $null

try {
    $protocolKey.SetValue('', 'URL:Secure Vault Protocol', [Microsoft.Win32.RegistryValueKind]::String)
    $protocolKey.SetValue('URL Protocol', '', [Microsoft.Win32.RegistryValueKind]::String)
    $commandKey = $protocolKey.CreateSubKey('shell\open\command')
    $commandKey.SetValue(
        '',
        ('"{0}" "%1"' -f $resolvedExecutable),
        [Microsoft.Win32.RegistryValueKind]::String)
}
finally {
    if ($commandKey) {
        $commandKey.Dispose()
    }
    if ($protocolKey) {
        $protocolKey.Dispose()
    }
}

Write-Output "Registered securevault:// to open $resolvedExecutable"
Write-Output 'Type securevault://open in the browser address bar and press Enter.'
