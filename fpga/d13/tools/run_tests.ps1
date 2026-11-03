param(
    [string]$VivadoBin = 'D:\AMDDesignTools\2025.2\Vivado\bin',
    [string]$WorkSubdir = 'xsim_work',
    [switch]$Optimize,
    [string[]]$Benches = @('tb_piano_osc','tb_pt8211_tx','tb_mcp3008_scan','tb_controls_pressure_allocator','tb_voice_engine_tone','tb_full_top','tb_spectrum_fft','tb_spectrum_video','tb_spectrum_animation','tb_visual_top','tb_engine28','tb_scan28','tb_pressure28','tb_video28','tb_full28','tb_light_ripple28','tb_ws2812_frame_tx','tb_audio_status28','tb_cold_start28','tb_single_key28','tb_touch_ui28','tb_master_volume28','tb_touch_video28','tb_touch_system28','tb_ws170120_reports','tb_touch_frame_cdc','tb_usb_fs_phy60','tb_ws170120_usb_host','tb_touch_usb_system28','tb_usb_reject_pid','tb_usb_reject_endpoint','tb_usb_diag_bridge','tb_usb_diag_video','tb_physical_key_isolation28','tb_usb_diag_no_response','tb_usb_session_guard','tb_usb_guarded_startup','tb_touch_manual_usb_system28','tb_touch_usb_clock_fault28','tb_usb_dual_path_monitor','tb_pitch_ui28','tb_pitch_controls28','tb_pitch_audio28')
)
$ErrorActionPreference = 'Stop'
$pianoRoot = Split-Path $PSScriptRoot -Parent
$workDir = Join-Path (Join-Path $pianoRoot 'reports') $WorkSubdir
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $pianoRoot 'rom') -Destination $workDir -Recurse -Force
Get-ChildItem -LiteralPath (Join-Path $pianoRoot 'sim') -Filter '*.hex*' | Copy-Item -Destination $workDir -Force
$sourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $pianoRoot 'src') -Filter '*.v' | ForEach-Object FullName)
$benchFiles = @(Get-ChildItem -LiteralPath (Join-Path $pianoRoot 'sim') -Filter '*.sv' | ForEach-Object FullName)
$testInputHashes=[ordered]@{}
foreach($testFolder in @('src','rom','sim')){
    foreach($testFile in (Get-ChildItem -LiteralPath (Join-Path $pianoRoot $testFolder) -Recurse -File)){
        $testInputHashes[$testFile.FullName]=(Get-FileHash -LiteralPath $testFile.FullName -Algorithm SHA256).Hash
    }
}
$testInputHashes | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $workDir 'test_input_hashes.json') -Encoding utf8
[ordered]@{Status='RUNNING';Benches=$Benches} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $workDir 'test_driver.json') -Encoding utf8
function Invoke-Checked([string]$exe, [string[]]$arguments, [string]$logPath) {
    & $exe @arguments 2>&1 | Tee-Object -FilePath $logPath
    if ($LASTEXITCODE -ne 0) { throw "执行失败：$exe" }
    if (Select-String -LiteralPath $logPath -Pattern 'FATAL|Fatal:|^ERROR' -Quiet) { throw "检查日志：$logPath" }
}
Push-Location $workDir
try {
    # 使用响应文件，避免新增验证文件后超过Windows批处理8191字符上限。
    $compileArgs=@('-sv','-d','PIANO_XSIM')+@(($sourceFiles+$benchFiles) | ForEach-Object {'"'+$_.Replace('\','/')+'"'})
    $compileArgs | Set-Content -LiteralPath compile_files.rsp -Encoding utf8
    Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') @('-f','compile_files.rsp') 'compile.log'
    foreach ($bench in $benches) {
        $elabArgs=if($Optimize){@($bench,'-debug','off','-s',$bench)}else{@($bench,'-debug','typical','-s',$bench)}
        Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') $elabArgs "$bench.elaborate.log"
        Invoke-Checked (Join-Path $VivadoBin 'xsim.bat') @($bench,'-runall') "$bench.run.log"
        if (!(Select-String -LiteralPath "$bench.run.log" -Pattern '^PASS ' -Quiet)) { throw "$bench 未报告 PASS" }
    }
    foreach($testPath in $testInputHashes.Keys){
        if((Get-FileHash -LiteralPath $testPath -Algorithm SHA256).Hash -ne $testInputHashes[$testPath]){throw "仿真期间源码已改变：$testPath"}
    }
    [ordered]@{Status='PASS';Benches=$Benches;FinishedUtc=(Get-Date).ToUniversalTime().ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $workDir 'test_driver.json') -Encoding utf8
    Write-Output ('PASS: all ' + $Benches.Count + ' requested self-checking simulations')
} finally { Pop-Location }
