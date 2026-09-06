param(
    [string]$GodotExe = $env:MEYUI_GODOT_EXE,
    [switch]$Play
)
$ErrorActionPreference = 'Stop'
if (-not $GodotExe) {
    $downloadFolder = Join-Path $env:USERPROFILE 'Downloads'
    $candidates = @(Get-ChildItem -LiteralPath $downloadFolder -Filter 'Godot*' -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Filter 'Godot*_win64.exe' -File })
    $selected = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($selected) { $GodotExe = $selected.FullName }
}
if (-not $GodotExe -or -not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw 'Informe o executável: .\open.ps1 -GodotExe "C:\Godot\Godot.exe"'
}
$engineArguments = @('--path', ('"' + $PSScriptRoot + '"'))
if (-not $Play) { $engineArguments += @('--editor', 'res://scenes/main.tscn') }
Start-Process -FilePath $GodotExe -ArgumentList $engineArguments -WindowStyle Normal
