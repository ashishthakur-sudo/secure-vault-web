$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$iconRenderer = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

public static class SecureVaultIconRenderer
{
    public static Bitmap Render(int size)
    {
        var bitmap = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(bitmap))
        using (var background = new SolidBrush(Color.FromArgb(255, 16, 30, 53)))
        using (var shield = new SolidBrush(Color.FromArgb(255, 64, 211, 190)))
        using (var lockBody = new SolidBrush(Color.FromArgb(255, 16, 30, 53)))
        using (var keyhole = new SolidBrush(Color.FromArgb(255, 180, 255, 237)))
        using (var shieldPath = new GraphicsPath())
        using (var backgroundPath = new GraphicsPath())
        using (var shackle = new GraphicsPath())
        using (var shacklePen = new Pen(Color.FromArgb(255, 16, 30, 53), 58))
        using (var keyholePath = new GraphicsPath())
        {
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
            graphics.ScaleTransform(size / 1024f, size / 1024f);

            AddRoundedRectangle(backgroundPath, 40, 40, 944, 944, 218);
            graphics.FillPath(background, backgroundPath);

            shieldPath.AddPolygon(new[]
            {
                new PointF(512, 154),
                new PointF(786, 260),
                new PointF(755, 552),
                new PointF(646, 716),
                new PointF(512, 824),
                new PointF(378, 716),
                new PointF(269, 552),
                new PointF(238, 260),
            });
            graphics.FillPath(shield, shieldPath);

            shackle.StartFigure();
            shackle.AddLine(new PointF(399, 470), new PointF(399, 370));
            shackle.AddBezier(
                new PointF(399, 370),
                new PointF(399, 244),
                new PointF(625, 244),
                new PointF(625, 370));
            shackle.AddLine(new PointF(625, 370), new PointF(625, 470));
            shacklePen.StartCap = LineCap.Round;
            shacklePen.EndCap = LineCap.Round;
            graphics.DrawPath(shacklePen, shackle);

            using (var bodyPath = new GraphicsPath())
            {
                AddRoundedRectangle(bodyPath, 322, 412, 380, 302, 64);
                graphics.FillPath(lockBody, bodyPath);
            }

            keyholePath.AddEllipse(474, 490, 76, 76);
            keyholePath.AddPolygon(new[]
            {
                new PointF(490, 550),
                new PointF(534, 550),
                new PointF(555, 624),
                new PointF(469, 624),
            });
            graphics.FillPath(keyhole, keyholePath);
        }

        return bitmap;
    }

    public static void WritePng(string path, int size)
    {
        using (var bitmap = Render(size))
        {
            bitmap.Save(path, ImageFormat.Png);
        }
    }

    public static void WriteIco(string path)
    {
        int[] sizes = { 16, 24, 32, 48, 64, 128, 256 };
        var frames = new byte[sizes.Length][];
        for (int i = 0; i < sizes.Length; i++)
        {
            using (var bitmap = Render(sizes[i]))
            using (var stream = new MemoryStream())
            {
                bitmap.Save(stream, ImageFormat.Png);
                frames[i] = stream.ToArray();
            }
        }

        using (var file = File.Create(path))
        using (var writer = new BinaryWriter(file))
        {
            writer.Write((ushort)0);
            writer.Write((ushort)1);
            writer.Write((ushort)sizes.Length);

            int offset = 6 + sizes.Length * 16;
            for (int i = 0; i < sizes.Length; i++)
            {
                byte dimension = sizes[i] == 256 ? (byte)0 : (byte)sizes[i];
                writer.Write(dimension);
                writer.Write(dimension);
                writer.Write((byte)0);
                writer.Write((byte)0);
                writer.Write((ushort)1);
                writer.Write((ushort)32);
                writer.Write((uint)frames[i].Length);
                writer.Write((uint)offset);
                offset += frames[i].Length;
            }

            foreach (byte[] frame in frames)
            {
                writer.Write(frame);
            }
        }
    }

    private static void AddRoundedRectangle(
        GraphicsPath path,
        float x,
        float y,
        float width,
        float height,
        float radius)
    {
        float diameter = radius * 2;
        path.AddArc(x, y, diameter, diameter, 180, 90);
        path.AddArc(x + width - diameter, y, diameter, diameter, 270, 90);
        path.AddArc(
            x + width - diameter,
            y + height - diameter,
            diameter,
            diameter,
            0,
            90);
        path.AddArc(x, y + height - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
    }
}
'@

Add-Type -TypeDefinition $iconRenderer -ReferencedAssemblies 'System.Drawing'

$projectRoot = Split-Path -Parent $PSScriptRoot
$androidIcons = @{
    'mipmap-mdpi' = 48
    'mipmap-hdpi' = 72
    'mipmap-xhdpi' = 96
    'mipmap-xxhdpi' = 144
    'mipmap-xxxhdpi' = 192
}

foreach ($density in $androidIcons.Keys) {
    $directory = Join-Path $projectRoot "android\app\src\main\res\$density"
    [SecureVaultIconRenderer]::WritePng(
        (Join-Path $directory 'ic_launcher.png'),
        $androidIcons[$density])
}

$windowsIcon = Join-Path $projectRoot 'windows\runner\resources\app_icon.ico'
[SecureVaultIconRenderer]::WriteIco($windowsIcon)

$webIcons = @{
    'icons\Icon-192.png' = 192
    'icons\Icon-512.png' = 512
    'icons\Icon-maskable-192.png' = 192
    'icons\Icon-maskable-512.png' = 512
    'favicon.png' = 32
}

foreach ($icon in $webIcons.GetEnumerator()) {
    [SecureVaultIconRenderer]::WritePng(
        (Join-Path $projectRoot "web\$($icon.Key)"),
        $icon.Value)
}

Write-Output 'Generated matching Secure Vault Android, Windows, and web icons.'
