param([string]$GowinBin = 'D:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin', [switch]$PnROnly, [int]$TimeoutMinutes=35, [int]$AttachProcessId=0, [string]$OriginalStart='')
$ErrorActionPreference = 'Stop'
$pianoRoot = Split-Path $PSScriptRoot -Parent
$runner = Join-Path $GowinBin 'gw_sh.exe'
if (!(Test-Path -LiteralPath $runner)) { throw "找不到 Gowin：$runner" }
$buildLog = Join-Path $pianoRoot 'reports/implementation_console.log'
$stdoutLog = Join-Path $pianoRoot 'reports/implementation_stdout.log'
$stderrLog = Join-Path $pianoRoot 'reports/implementation_stderr.log'
$bitstream = Join-Path $pianoRoot 'impl/pnr/pressure_piano_touch.fs'
$buildStarted = if ($OriginalStart) { [datetime]::Parse($OriginalStart) } else { Get-Date }
# 新一轮实现开始即撤销上轮完成标志，防止复用旧报告/位流误判。
[ordered]@{StartedUtc=$buildStarted.ToUniversalTime().ToString('o');Supervisor=$PID;PnROnly=[bool]$PnROnly} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $pianoRoot 'reports/active_implementation.json') -Encoding utf8
[ordered]@{CompletedTcl=$false;ValidatedFreshBitstream=$false;SetupHoldZero=$false;Status='RUNNING'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $pianoRoot 'reports/implementation_driver.json') -Encoding utf8
if ($PnROnly) {
    $previousInputs = Get-Content -LiteralPath (Join-Path $pianoRoot 'reports/touch_build_inputs.json') -Raw | ConvertFrom-Json
    foreach ($entry in $previousInputs.PSObject.Properties) {
        if ($entry.Name -notmatch '[/\\]constraints[/\\]') {
            if ((Get-FileHash -LiteralPath $entry.Name -Algorithm SHA256).Hash -ne $entry.Value) {
                if ($entry.Name -like '*_process_config.json' -and (Test-Path -LiteralPath (Join-Path $pianoRoot 'reports/implementation_process_config_snapshot.json'))) {
                    # 原配置必须与上轮构建哈希相符；仅允许更换官方PnR算法，器件/电压/IO/综合参数逐项保持。
                    $configSnapshot=Join-Path $pianoRoot 'reports/implementation_process_config_snapshot.json'
                    if ((Get-FileHash -LiteralPath $configSnapshot -Algorithm SHA256).Hash -ne $entry.Value) { throw '缺少与综合网表对应的原配置快照。' }
                    $baseConfig=Get-Content -LiteralPath $configSnapshot -Raw | ConvertFrom-Json -AsHashtable
                    $nowConfig=Get-Content -LiteralPath $entry.Name -Raw | ConvertFrom-Json -AsHashtable
                    $allConfigKeys=@($baseConfig.Keys)+@($nowConfig.Keys)
                    foreach($key in ($allConfigKeys | Select-Object -Unique)){
                        if($key -notin @('Place_Option','Route_Option','Replicate_Resources')){
                            if(($baseConfig[$key] | ConvertTo-Json -Compress) -ne ($nowConfig[$key] | ConvertTo-Json -Compress)){throw "非PnR选项改变，禁止复用综合网表：$key"}
                        }
                    }
                    if([int]$nowConfig.Place_Option -notin 0..4 -or [int]$nowConfig.Route_Option -notin 0..2){throw '不支持的PnR算法'}
                } else {throw "源码已变，不能复用综合网表：$($entry.Name)"}
            }
        }
    }
    $synthesizedNetlist = Get-Item -LiteralPath (Join-Path $pianoRoot 'impl/gwsynthesis/pressure_piano_touch.vg')
    if (Get-ChildItem -LiteralPath (Join-Path $pianoRoot 'src') -Recurse -File | Where-Object LastWriteTime -gt $synthesizedNetlist.LastWriteTime) { throw '综合网表早于源码，必须完整重建。' }
}
$buildInputHashes = [ordered]@{}
$buildInputFiles = @()
foreach ($subdirectory in @('src','constraints','rom')) {
    $buildInputFiles += @(Get-ChildItem -LiteralPath (Join-Path $pianoRoot $subdirectory) -Recurse -File)
}
$buildInputFiles += Get-Item -LiteralPath (Join-Path $pianoRoot 'pressure_piano_touch.gprj')
$pianoProcessConfig = Join-Path $pianoRoot 'impl/pressure_piano_touch_process_config.json'
if (Test-Path -LiteralPath $pianoProcessConfig) {
    $buildInputFiles += Get-Item -LiteralPath $pianoProcessConfig # GUI过程选项也是构建输入，不能在实现中途修改。
}
foreach ($inputFile in $buildInputFiles) { $buildInputHashes[$inputFile.FullName] = (Get-FileHash -LiteralPath $inputFile.FullName -Algorithm SHA256).Hash }
if ($PnROnly) { $buildInputHashes[$synthesizedNetlist.FullName] = (Get-FileHash -LiteralPath $synthesizedNetlist.FullName -Algorithm SHA256).Hash }
$buildInputHashes | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $pianoRoot 'reports/touch_build_inputs.json') -Encoding utf8
Copy-Item -LiteralPath $pianoProcessConfig -Destination (Join-Path $pianoRoot 'reports/implementation_process_config_snapshot.json') -Force
$buildProcess = $null
$forcedShellExit = $false
Push-Location $pianoRoot
try {
    # 隐藏的本任务子进程；只在Tcl已明确完成且报告校验通过后处理版本相关的退出滞留。
    $buildTcl = if ($PnROnly) { 'tools/implement_pnr.tcl' } else { 'tools/implement.tcl' }
    if ($AttachProcessId -gt 0) {
        $buildProcess = Get-Process -Id $AttachProcessId -ErrorAction Stop
        $null = $buildProcess.Handle # 保持原求解进程的句柄；只接管监控，不重启求解。
        [ordered]@{compiler=$AttachProcessId;supervisor=$PID;originalStart=$buildStarted.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $pianoRoot 'reports/monitor_attached.json') -Encoding utf8
    } else {
        $buildProcess = Start-Process -FilePath $runner -ArgumentList $buildTcl -WorkingDirectory $pianoRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
    }
    $finishSeen = $null
    while (!$buildProcess.HasExited) {
        $buildProcess.Refresh()
        if ((Test-Path -LiteralPath $stdoutLog) -and (Select-String -LiteralPath $stdoutLog -Pattern '^CODEX_IMPLEMENTATION_FINISHED\s*$' -Quiet)) {
            if ($null -eq $finishSeen) { $finishSeen = Get-Date }
            if (((Get-Date)-$finishSeen).TotalSeconds -ge 10) { $forcedShellExit = $true; break }
        }
        if (((Get-Date)-$buildStarted).TotalMinutes -ge $TimeoutMinutes) { throw '实现超时；未以旧位流判定通过。' }
        Start-Sleep -Milliseconds 250
    }
    $combinedLog = (Get-Content -LiteralPath $stdoutLog -Raw) + "`n" + (Get-Content -LiteralPath $stderrLog -Raw -ErrorAction SilentlyContinue)
    $combinedLog | Set-Content -LiteralPath $buildLog -Encoding utf8
    if (!$forcedShellExit -and $buildProcess.ExitCode -ne 0) { throw '实现进程返回失败，请检查布局布线日志。' }
    if ($combinedLog -notmatch '(?m)^CODEX_IMPLEMENTATION_FINISHED\s*$') { throw 'Tcl未确认完整流程返回，不能将部分输出当成最终结果。' }
    if ($combinedLog -match 'invalid command name|while executing|Tcl Error') { throw 'Tcl脚本错误，不能标记完成。' }
    if (Select-String -LiteralPath $buildLog -Pattern '^\s*ERROR' -Quiet) { throw '实现日志中存在错误。' }
    if (!(Test-Path -LiteralPath $bitstream)) { throw '没有生成位流文件。' }
    if ((Get-Item -LiteralPath $bitstream).LastWriteTime -lt $buildStarted) { throw '位流没有更新，不能使用旧文件作为本次结果。' }
    if (!(Select-String -LiteralPath $buildLog -Pattern 'Bitstream generation completed' -Quiet)) { throw '日志未确认位流生成完成。' }
    if (Select-String -LiteralPath $buildLog -Pattern 'TA1123|PA2078|PA1019' -Quiet) { throw 'PLL 参数或约束频率不一致，不能将本次位流标记为可下载。' }
    $timingReport = Join-Path $pianoRoot 'impl/pnr/pressure_piano_touch_tr_content.html'
    $timingText = [regex]::Replace((Get-Content -LiteralPath $timingReport -Raw), '<[^>]+>', ' ')
    $timingText = [regex]::Replace($timingText, '\s+', ' ')
    foreach ($analysis in @('Setup','Hold')) {
        if ($timingText -notmatch ("Numbers of $analysis Violated Endpoints 0\b")) { throw "$analysis 时序未确认零违例。" }
    }
    foreach ($analysis in @('Recovery','Removal')) {
        $resetSlack=[regex]::Match($timingText,("$analysis Paths Table.*?Data Delay\s+1\s+([-+]?\d+\.\d+)"))
        if ($resetSlack.Success -and [double]$resetSlack.Groups[1].Value -lt 0) { throw "$analysis 复位时序存在违例。" }
    }
    if (!(Select-String -LiteralPath (Join-Path $pianoRoot 'impl/pnr/device.cfg') -Pattern '^set vccx = 1\.8\s*$' -Quiet)) { throw '当前60K工程的VCCX应为1.8，请核查配置。' }
    foreach ($inputPath in $buildInputHashes.Keys) {
        if ((Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash -ne $buildInputHashes[$inputPath]) { throw "构建期间源码发生变化，须重新实现：$inputPath" }
    }
    if ($forcedShellExit) {
        Stop-Process -Id $buildProcess.Id -ErrorAction Stop
        Write-Output 'Tcl完成标记、新位流、零违例报告均已确认；已关闭结束后仍滞留的本任务Gowin命令行进程。'
    }
    $synthesisActuallyReused=[bool]$PnROnly -and $combinedLog -notmatch 'GowinSynthesis start'
    [ordered]@{CompletedTcl=$true;ValidatedFreshBitstream=$true;SetupHoldZero=$true;RequestedPnROnly=[bool]$PnROnly;ReusedSynthesis=$synthesisActuallyReused;SupervisorReattached=($AttachProcessId -gt 0);ShellStoppedAfterCompleted=$forcedShellExit} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $pianoRoot 'reports/implementation_driver.json') -Encoding utf8
    Write-Output "已生成匹配当前约束的位流：$bitstream"
} catch {
    # 失败时撤销运行中状态；后续交付脚本仍必须通过全部完成标志。
    [ordered]@{CompletedTcl=$false;ValidatedFreshBitstream=$false;SetupHoldZero=$false;Status='FAILED';Error=$_.Exception.Message;FailedUtc=(Get-Date).ToUniversalTime().ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $pianoRoot 'reports/implementation_driver.json') -Encoding utf8
    throw
} finally {
    if ($null -ne $buildProcess) {
        $buildProcess.Refresh()
        if (!$buildProcess.HasExited) { Stop-Process -Id $buildProcess.Id -ErrorAction SilentlyContinue }
    }
    Pop-Location
}
