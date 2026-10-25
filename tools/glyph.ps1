# Rasterize one character to a 20x20 bitmap ('1' = ink), Microsoft YaHei.
# Size 20 / threshold 96 matches the existing circle_font_rom glyphs.
param([string]$Text, [float]$Size = 20, [int]$Dx = 0, [int]$Dy = 0, [int]$Thr = 96)
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap 20, 20
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::Black)
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$font = New-Object System.Drawing.Font('Microsoft YaHei', $Size, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$fmt = New-Object System.Drawing.StringFormat
$fmt.Alignment = [System.Drawing.StringAlignment]::Center
$fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
$rect = New-Object System.Drawing.RectangleF ([float]$Dx), ([float]$Dy), 20, 20
$g.DrawString($Text, $font, [System.Drawing.Brushes]::White, $rect, $fmt)
for ($y = 0; $y -lt 20; $y++) {
    $line = ''
    for ($x = 0; $x -lt 20; $x++) {
        if ($bmp.GetPixel($x, $y).R -ge $Thr) { $line += '1' } else { $line += '0' }
    }
    $line
}
