$ErrorActionPreference = 'Stop'
$taskProject = Split-Path -Parent $PSScriptRoot
$taskCompiler = Join-Path $taskProject 'tools/iverilog/app/bin/iverilog.exe'
$taskSimulator = Join-Path $taskProject 'tools/iverilog/app/bin/vvp.exe'
Push-Location -LiteralPath $taskProject
try {
    & $taskCompiler -g2012 -I src/edge -s tb_sobel_video -o sim/tb_sobel_video.vvp src/edge/rgb565_gray.v src/edge/median3x3_video.v src/edge/sobel_video.v sim/tb_sobel_video.v
    if ($LASTEXITCODE -ne 0) { throw 'Sobel simulation compilation failed' }
    & $taskSimulator sim/tb_sobel_video.vvp
    if ($LASTEXITCODE -ne 0) { throw 'Sobel simulation failed' }
    & $taskCompiler -g2012 -I src/edge -s tb_sobel_video '-Ptb_sobel_video.TEST_MEDIAN=1' -o sim/tb_median_sobel.vvp src/edge/rgb565_gray.v src/edge/median3x3_video.v src/edge/sobel_video.v sim/tb_sobel_video.v
    if ($LASTEXITCODE -ne 0) { throw 'Median/Sobel simulation compilation failed' }
    & $taskSimulator sim/tb_median_sobel.vvp
    if ($LASTEXITCODE -ne 0) { throw 'Median/Sobel simulation failed' }
    & $taskCompiler -g2012 -s tb_median_gaussian_stream -o sim/tb_median_gaussian_stream.vvp src/edge/median3x3_video.v src/edge/gaussian_stream.v sim/tb_median_gaussian_stream.v
    if ($LASTEXITCODE -ne 0) { throw 'Median/Gaussian stream simulation compilation failed' }
    & $taskSimulator sim/tb_median_gaussian_stream.vvp
    if ($LASTEXITCODE -ne 0) { throw 'Median/Gaussian stream simulation failed' }
    & $taskCompiler -g2012 -s tb_overlay_phase -o sim/tb_overlay_phase.vvp src/edge/median3x3_video.v src/edge/gaussian_stream.v src/edge/sobel_stream.v src/edge/hysteresis_stream.v src/edge/edge_frame_hold.v src/edge/rgb565_frame_align.v sim/tb_overlay_phase.v
    if ($LASTEXITCODE -ne 0) { throw 'Colour overlay alignment compilation failed' }
    & $taskSimulator sim/tb_overlay_phase.vvp
    if ($LASTEXITCODE -ne 0) { throw 'Colour overlay alignment failed' }
    & $taskCompiler -g2012 -s tb_overlay_gaussian_only -o sim/tb_overlay_gaussian_only.vvp src/edge/gaussian_stream.v src/edge/sobel_stream.v src/edge/hysteresis_stream.v src/edge/edge_frame_hold.v src/edge/rgb565_frame_align.v sim/tb_overlay_gaussian_only.v
    if ($LASTEXITCODE -ne 0) { throw 'Gaussian-only overlay alignment compilation failed' }
    & $taskSimulator sim/tb_overlay_gaussian_only.vvp
    if ($LASTEXITCODE -ne 0) { throw 'Gaussian-only overlay alignment failed' }
    & $taskCompiler -g2012 -s tb_edge_temporal_sticky -o sim/tb_edge_temporal_sticky.vvp src/edge/edge_temporal_sticky.v sim/tb_edge_temporal_sticky.v
    if ($LASTEXITCODE -ne 0) { throw 'Temporal ridge hysteresis compilation failed' }
    & $taskSimulator sim/tb_edge_temporal_sticky.vvp
    if ($LASTEXITCODE -ne 0) { throw 'Temporal ridge hysteresis simulation failed' }
    & $taskCompiler -g2012 -s tb_circle_geometry_detector -o sim/tb_circle_geometry_detector.vvp src/edge/circle_geometry_detector.v sim/tb_circle_geometry_detector.v
    if ($LASTEXITCODE -ne 0) { throw 'Circle geometry simulation compilation failed' }
    & $taskSimulator sim/tb_circle_geometry_detector.vvp
    if ($LASTEXITCODE -ne 0) { throw 'Circle geometry simulation failed' }
    & $taskCompiler -g2012 -s tb_circle_label_osd -o sim/tb_circle_label_osd.vvp src/edge/circle_label_osd.v src/edge/circle_font_rom.v sim/tb_circle_label_osd.v
    if ($LASTEXITCODE -ne 0) { throw 'Circle annotation compilation failed' }
    & $taskSimulator sim/tb_circle_label_osd.vvp
    if ($LASTEXITCODE -ne 0) { throw 'Circle annotation simulation failed' }
    & $taskCompiler -g2012 -s tb_key_threshold -o sim/tb_key_threshold.vvp src/edge/key_threshold.v sim/tb_key_threshold.v
    if ($LASTEXITCODE -ne 0) { throw 'Key simulation compilation failed' }
    & $taskSimulator sim/tb_key_threshold.vvp
    if ($LASTEXITCODE -ne 0) { throw 'Key simulation failed' }
    & $taskCompiler -g2012 -s tb_camera_fps -o sim/tb_camera_fps.vvp src/edge/camera_fps.v sim/tb_camera_fps.v
    if ($LASTEXITCODE -ne 0) { throw 'FPS simulation compilation failed' }
    & $taskSimulator sim/tb_camera_fps.vvp
    if ($LASTEXITCODE -ne 0) { throw 'FPS simulation failed' }
} finally {
    Pop-Location
}
