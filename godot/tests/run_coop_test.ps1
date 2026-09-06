param(
    [string]$Godot = 'C:\Users\jarom\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe',
    [int]$Port = 27943
)
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$output = Join-Path $project "test-output\coop_$stamp"
New-Item -ItemType Directory -Path $output -Force | Out-Null
$common = @('--headless', '--path', ('"' + $project + '"'), '--script', 'res://tests/test_coop.gd', '--', "--port=$Port", ('"--output=' + $output.Replace('\', '/') + '"'))
$hostProcess = Start-Process -FilePath $Godot -ArgumentList ($common + '--role=host') -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $output 'host.log') -RedirectStandardError (Join-Path $output 'host.err.log')
$deadline = [DateTime]::UtcNow.AddSeconds(30)
while (-not (Test-Path -LiteralPath (Join-Path $output 'ready'))) {
    if ($hostProcess.HasExited -or [DateTime]::UtcNow -gt $deadline) { throw "Host did not become ready: $output" }
    Start-Sleep -Milliseconds 100
}
$clientProcess = Start-Process -FilePath $Godot -ArgumentList ($common + '--role=client') -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $output 'client.log') -RedirectStandardError (Join-Path $output 'client.err.log')
[pscustomobject]@{ Output = $output; HostPid = $hostProcess.Id; ClientPid = $clientProcess.Id } | ConvertTo-Json -Compress
$deadline = [DateTime]::UtcNow.AddSeconds(75)
while (-not $hostProcess.HasExited -or -not $clientProcess.HasExited) {
    if ([DateTime]::UtcNow -gt $deadline) { throw "Test exceeded its own watchdog: $output" }
    Start-Sleep -Milliseconds 100
}
$hostProcess.Refresh()
$clientProcess.Refresh()
$hostResult = Get-Content -LiteralPath (Join-Path $output 'host_result.json') -Raw | ConvertFrom-Json
$clientResult = Get-Content -LiteralPath (Join-Path $output 'client_result.json') -Raw | ConvertFrom-Json
$errors = @((Get-Content -LiteralPath (Join-Path $output 'host.err.log')), (Get-Content -LiteralPath (Join-Path $output 'client.err.log'))) | Where-Object { $_ -match 'ERROR:|WARNING:' }
if (-not $hostResult.ok -or -not $clientResult.ok -or $errors.Count -gt 0) { throw "Co-op validation failed: $output" }
[pscustomobject]@{ Passed = $true; Checks = $hostResult.checks + $clientResult.checks; Output = $output } | ConvertTo-Json -Compress
