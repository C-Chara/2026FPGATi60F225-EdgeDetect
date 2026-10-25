# Full Efinity compile, then copy the bitstream and reports to tagged names:
#   outflow\Ti60_Demo_<Tag>_<yyyyMMdd>.bit / .timing.rpt / .place.rpt
# Usage: powershell -ExecutionPolicy Bypass -File tools\build_tagged.ps1 -Tag my_change
param([Parameter(Mandatory = $true)][string]$Tag)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$setup = 'D:\FPGA\Tools\efinity-2026.1.132-windows-x64\efinity\2026.1\bin\setup.bat'
Set-Location -LiteralPath $project
$log = Join-Path $env:TEMP "efx_compile_$Tag.log"
cmd /c "`"$setup`" && efx_run.bat Ti60_Demo.xml --prj --flow compile > `"$log`" 2>&1"
if ($LASTEXITCODE -ne 0) { throw "compile failed for $Tag, see $log" }
$date = Get-Date -Format yyyyMMdd
foreach ($ext in 'bit', 'timing.rpt', 'place.rpt') {
    Copy-Item "outflow\Ti60_Demo.$ext" "outflow\Ti60_Demo_${Tag}_$date.$ext" -Force
}
$usercode = Select-String -LiteralPath 'Ti60_Demo.xml' -Pattern 'jtag_usercode" value="([^"]+)"' |
    ForEach-Object { $_.Matches[0].Groups[1].Value }
"built outflow\Ti60_Demo_${Tag}_$date.bit, USERCODE $usercode"
