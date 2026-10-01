param(
    [Parameter(Mandatory = $true)]
    [string]$InputPng,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

# Tile and splash images referenced by AppxManifest.xml. The icon is centered on a transparent
# canvas, scaled to the given height.
$logos = @(
    @{ Name = "StoreLogo.png"; Width = 50; Height = 50; IconSize = 50 },
    @{ Name = "Square44x44Logo.png"; Width = 44; Height = 44; IconSize = 44 },
    @{ Name = "Square150x150Logo.png"; Width = 150; Height = 150; IconSize = 120 },
    @{ Name = "Wide310x150Logo.png"; Width = 310; Height = 150; IconSize = 120 },
    @{ Name = "SplashScreen.png"; Width = 620; Height = 300; IconSize = 240 }
)

$inputPath = (Resolve-Path $InputPng).Path
$outputPath = [System.IO.Path]::GetFullPath($OutputDir)
[System.IO.Directory]::CreateDirectory($outputPath) | Out-Null

$sourceImage = [System.Drawing.Image]::FromFile($inputPath)
try {
    foreach ($logo in $logos) {
        $bitmap = New-Object System.Drawing.Bitmap $logo.Width, $logo.Height
        try {
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.Clear([System.Drawing.Color]::Transparent)
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $x = [int](($logo.Width - $logo.IconSize) / 2)
                $y = [int](($logo.Height - $logo.IconSize) / 2)
                $graphics.DrawImage($sourceImage, $x, $y, $logo.IconSize, $logo.IconSize)
            } finally {
                $graphics.Dispose()
            }
            $bitmap.Save((Join-Path $outputPath $logo.Name), [System.Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $bitmap.Dispose()
        }
    }
} finally {
    $sourceImage.Dispose()
}
