param([string]$WorkSubdir='xsim_d12_regression')
$ErrorActionPreference='Stop'
$d12Root=Split-Path $PSScriptRoot -Parent
# 完整30项数字回归；额外覆盖USB校验流水线的正常与错误设备描述符。
& (Join-Path $PSScriptRoot 'run_tests.ps1') -Optimize -WorkSubdir $WorkSubdir -Benches @(
 'tb_d12_key_decoder','tb_d12_wishbone','tb_d12_volume_pipeline','tb_d12_game_timing','tb_d12_ui_pipeline','tb_game_engine28','tb_game_five_minutes','tb_d12_guide_led','tb_d12_effect_controls','tb_ch569_gpio_link','tb_d12_ui',
 'tb_timbre_engine','tb_timbre_pressure','tb_d12_equivalence','tb_timbre_d11_context',
 'tb_media_ui','tb_timbre_ui','tb_media_audio','tb_progress_lookup','tb_media_video','tb_ws2812_frame_tx',
 'tb_touch_manual_usb_system28','tb_touch_usb_clock_fault28','tb_physical_key_isolation28','tb_timbre_system','tb_media_boot','tb_d12_game_cpu',
 'tb_ws170120_usb_host','tb_usb_reject_pid','tb_usb_reject_endpoint')
if($LASTEXITCODE -ne 0){throw 'D12 regression failed'}
