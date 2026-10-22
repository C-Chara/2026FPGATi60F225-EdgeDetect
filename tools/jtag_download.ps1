# JTAG download (volatile: lost on power-off or K3 reset).
# Usage, from any PowerShell window:
#   powershell -ExecutionPolicy Bypass -File tools\jtag_download.ps1 outflow\<name>.bit
param([Parameter(Mandatory = $true)][string]$Bit)
$ErrorActionPreference = 'Stop'
$efinity = 'D:\FPGA\Tools\efinity-2026.1.132-windows-x64\efinity\2026.1'
$url = 'ftdi://0x0403:0x6014:0:1/1'
$bitPath = (Resolve-Path -LiteralPath $Bit).Path
$status = Join-Path $PSScriptRoot 'jtag_status.py'
$env:EFINITY_USER_DIR = "$env:USERPROFILE\.efinity"
$setup = "`"$efinity\bin\setup.bat`""

"1/3 Looking for the FPGA on the JTAG chain..."
$chain = cmd /c "$setup && python `"$efinity\pgm\bin\jtag_chain_detect.py`" -f $url 2>&1"
$chain | Select-Object -Last 3
if (-not ($chain -match '0x10660a79')) {
    throw 'No Ti60 found. Check board power and the JTAG cable, then try again.'
}

"2/3 Downloading $bitPath ..."
cmd /c "$setup && python `"$efinity\pgm\bin\efx_pgm\ftdi_program.py`" `"$bitPath`" -m jtag -b `"Generic Board Profile Using FT232H`" -u $url -a $url 2>&1" | Select-Object -Last 2

"3/3 Reading back the device status..."
cmd /c "$setup && python `"$status`" $url 2>&1" | Select-String 'PROG_STATE|CRC32|USERCODE' | ForEach-Object { $_.Line }
"Done if PROG_STATE is USER_MODE, both CRC32 errors are 0 and USERCODE matches the build."
