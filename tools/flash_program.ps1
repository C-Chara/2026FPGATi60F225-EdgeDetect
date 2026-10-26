# Write a build into the board's SPI flash so it starts at power-up.
#   1. JTAG-load the vendor JTAG-to-SPI bridge image into the FPGA
#   2. erase, write and verify the flash through the bridge (.hex file)
#   3. power-cycle the board, then check the USERCODE with tools\jtag_status.py
# Usage: powershell -ExecutionPolicy Bypass -File tools\flash_program.ps1 -Hex outflow\<name>.hex
param([Parameter(Mandatory = $true)][string]$Hex)
$ErrorActionPreference = 'Stop'
$efinity = 'D:\FPGA\Tools\efinity-2026.1.132-windows-x64\efinity\2026.1'
# Bridge image bundled with Efinity for IDCODE 0x10660A79 (the one the GUI programmer
# picks). The HDK's 2023.2 bridge reports version 0.0, which 2026.1 rejects.
$bridge = Join-Path $efinity 'pgm/fli/titanium/u10660A79.bit'
$url = 'ftdi://0x0403:0x6014:0:1/1'
$board = 'Generic Board Profile Using FT232H'
$hexPath = (Resolve-Path -LiteralPath $Hex).Path
if (-not (Test-Path -LiteralPath $bridge)) { throw "bridge image not found: $bridge" }
$env:EFINITY_USER_DIR = "$env:USERPROFILE\.efinity"
$setup = "`"$efinity\bin\setup.bat`""

"1/3 Looking for the FPGA on the JTAG chain..."
$chain = cmd /c "$setup && python `"$efinity\pgm\bin\jtag_chain_detect.py`" -f $url 2>&1"
$chain | Select-Object -Last 3
if (-not ($chain -match '0x10660a79')) {
    throw 'No Ti60 found. Check board power and the JTAG cable, then try again.'
}

"2/3 Loading the JTAG-to-SPI flash bridge..."
cmd /c "$setup && python `"$efinity\pgm\bin\efx_pgm\ftdi_program.py`" `"$bridge`" -m jtag -b `"$board`" -u $url -a $url 2>&1" | Select-Object -Last 3

"3/3 Erasing, writing and verifying the flash with $hexPath ..."
$out = cmd /c "$setup && python `"$efinity\pgm\bin\efx_pgm\ftdi_program.py`" `"$hexPath`" -m jtag_bridge -b `"$board`" -u $url -a $url 2>&1"
$out | Select-Object -Last 12
if ($LASTEXITCODE -ne 0 -or ($out -match 'ERROR')) { throw 'Flash programming reported an error (see above). The old flash content may be erased.' }
"Done. Power the board off and on: it now starts from flash. Check with:"
"  powershell -ExecutionPolicy Bypass -File tools\jtag_status_only.ps1"
