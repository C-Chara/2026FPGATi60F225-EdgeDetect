# Build the 60 fps colour release (current source), then the 30 fps colour
# variant (CAMERA_60FPS_RAW = 0, USERCODE + 1), and restore the source.
# Usage: powershell -ExecutionPolicy Bypass -File tools\build_both_colour.ps1 -Tag name
param([Parameter(Mandatory = $true)][string]$Tag)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$build = Join-Path $PSScriptRoot 'build_tagged.ps1'
$top = Join-Path $project 'example_top.v'
$xml = Join-Path $project 'Ti60_Demo.xml'
& $build -Tag "color_60fps_$Tag"
$topText = [System.IO.File]::ReadAllText($top)
$xmlText = [System.IO.File]::ReadAllText($xml)
try {
    $on = "localparam CAMERA_60FPS_RAW = 1'b1;"
    if (-not $topText.Contains($on)) { throw 'CAMERA_60FPS_RAW = 1 not found' }
    [System.IO.File]::WriteAllText($top, $topText.Replace($on, "localparam CAMERA_60FPS_RAW = 1'b0;"), (New-Object System.Text.UTF8Encoding $false))
    $m = [regex]::Match($xmlText, 'jtag_usercode" value="0x([0-9a-fA-F]+)"')
    $next = '{0:x8}' -f ([Convert]::ToUInt32($m.Groups[1].Value, 16) + 1)
    [System.IO.File]::WriteAllText($xml, $xmlText.Replace($m.Value, "jtag_usercode`" value=`"0x$next`""), (New-Object System.Text.UTF8Encoding $false))
    & $build -Tag "color_30fps_$Tag"
} finally {
    [System.IO.File]::WriteAllText($top, $topText, (New-Object System.Text.UTF8Encoding $false))
    [System.IO.File]::WriteAllText($xml, $xmlText, (New-Object System.Text.UTF8Encoding $false))
}
