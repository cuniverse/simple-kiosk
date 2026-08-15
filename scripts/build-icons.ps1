[CmdletBinding()]
param(
    [string]$Source
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if ([string]::IsNullOrWhiteSpace($Source)) {
    $Source = Join-Path $PSScriptRoot '..\assets\icons\simple-kiosk-logo.png'
}
$sourcePath = (Resolve-Path -LiteralPath $Source).Path
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$targets = @(
    (Join-Path $projectRoot 'assets\icons\simple_kiosk.ico'),
    (Join-Path $projectRoot 'windows\runner\resources\app_icon.ico')
)
$sizes = @(16, 24, 32, 48, 64, 128, 256)
$sourceImage = [System.Drawing.Image]::FromFile($sourcePath)
$streams = [System.Collections.Generic.List[System.IO.MemoryStream]]::new()

try {
    foreach ($size in $sizes) {
        $bitmap = [System.Drawing.Bitmap]::new(
            $size,
            $size,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        try {
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.Clear([System.Drawing.Color]::Transparent)
                $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
                $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.DrawImage($sourceImage, 0, 0, $size, $size)
            }
            finally {
                $graphics.Dispose()
            }
            $stream = [System.IO.MemoryStream]::new()
            $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
            $streams.Add($stream)
        }
        finally {
            $bitmap.Dispose()
        }
    }

    foreach ($target in $targets) {
        $output = [System.IO.File]::Open(
            $target,
            [System.IO.FileMode]::Create,
            [System.IO.FileAccess]::Write
        )
        $writer = [System.IO.BinaryWriter]::new($output)
        try {
            $writer.Write([UInt16]0)
            $writer.Write([UInt16]1)
            $writer.Write([UInt16]$streams.Count)
            $offset = 6 + (16 * $streams.Count)
            for ($index = 0; $index -lt $streams.Count; $index++) {
                $size = $sizes[$index]
                $length = [int]$streams[$index].Length
                $writer.Write([byte]($(if ($size -ge 256) { 0 } else { $size })))
                $writer.Write([byte]($(if ($size -ge 256) { 0 } else { $size })))
                $writer.Write([byte]0)
                $writer.Write([byte]0)
                $writer.Write([UInt16]1)
                $writer.Write([UInt16]32)
                $writer.Write([UInt32]$length)
                $writer.Write([UInt32]$offset)
                $offset += $length
            }
            foreach ($stream in $streams) {
                $writer.Write($stream.ToArray())
            }
        }
        finally {
            $writer.Dispose()
            $output.Dispose()
        }
        Write-Host "Created icon: $target"
    }
}
finally {
    foreach ($stream in $streams) { $stream.Dispose() }
    $sourceImage.Dispose()
}
