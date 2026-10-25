# Native Windows convenience runner. Install Python 3 and Icarus Verilog first.
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
python -m unittest discover -s tests -v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
python tools/regress.py --seeds 12 --length 180 --wave
exit $LASTEXITCODE
