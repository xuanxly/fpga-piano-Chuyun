param([string]$VivadoBin='D:\AMDDesignTools\2025.2\Vivado\bin')
$ErrorActionPreference='Stop'
$d13Root=Split-Path $PSScriptRoot -Parent
# 从本包历史审计读取34个测试名，日志写到新目录，保留发布时的历史证据。
$d13Audit=Get-Content -LiteralPath (Join-Path $d13Root 'reports/d13_verification.json') -Raw | ConvertFrom-Json
$d13Names=@($d13Audit.tests.PSObject.Properties.Name)
if($d13Names.Count -ne 34){throw 'Expected34 D13 tests'}
$d13Stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
& (Join-Path $PSScriptRoot 'run_tests.ps1') -VivadoBin $VivadoBin -Optimize -WorkSubdir "retest_d13_$d13Stamp" -Benches $d13Names
