# Read the running design's status and USERCODE over JTAG (nothing is written).
$ErrorActionPreference = 'Stop'
$efinity = 'D:\FPGA\Tools\efinity-2026.1.132-windows-x64\efinity\2026.1'
$url = 'ftdi://0x0403:0x6014:0:1/1'
$env:EFINITY_USER_DIR = "$env:USERPROFILE\.efinity"
$status = Join-Path $PSScriptRoot 'jtag_status.py'
cmd /c "`"$efinity\bin\setup.bat`" && python `"$status`" $url 2>&1" | Select-String 'PROG_STATE|CRC32|USERCODE|rror' | ForEach-Object { $_.Line }
