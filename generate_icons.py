#!/usr/bin/env python3
"""
Generate Pulse icons — Concept A
A single soundwave pulse line that subtly traces the shape of a "D".
One continuous stroke on dark background. Purple gradient.
"""

import math
import os
import subprocess
from PIL import Image, ImageDraw, ImageFilter, ImageChops

RESOURCES_DIR = os.path.join(os.path.dirname(__file__), "Resources")


def pulse_waveform(t, phase=0):
    """
    Generate the pulse waveform Y value for parameter t (0..1).
    The envelope forms a subtle "D" curve — flat on left, bulging right.
    """
    # D-shaped envelope: rises from left, peaks center-right, falls back
    # Using a skewed bell curve
    center = 0.55
    width_left = 0.22
    width_right = 0.18

    if t < center:
        dist = (t - center) / width_left
    else:
        dist = (t - center) / width_right

    envelope = math.exp(-0.5 * dist * dist)

    # Minimum envelope so the line is visible even at edges
    envelope = max(envelope, 0.05)

    # High-frequency oscillation (the actual waveform)
    freq = 14  # cycles across the path
    wave = math.sin(2 * math.pi * freq * t + phase)

    # Add a subtle second harmonic for richness
    wave += 0.3 * math.sin(2 * math.pi * freq * 2.1 * t + phase * 1.5)
    wave /= 1.3  # normalize

    return envelope * wave


def generate_waveform_points(width, height, margin_x=0.12, margin_y=0.2, num_points=500):
    """
    Generate list of (x, y) points for the pulse waveform.
    """
    points = []
    for i in range(num_points + 1):
        t = i / num_points
        x = margin_x * width + t * (1 - 2 * margin_x) * width
        y_norm = pulse_waveform(t)
        y = height / 2 - y_norm * (0.5 - margin_y) * height
        points.append((x, y))
    return points


def draw_gradient_line(draw, points, colors, line_width, img_size):
    """
    Draw a line with gradient color along its length.
    colors: list of (r,g,b) tuples for gradient stops.
    """
    n = len(points)
    for i in range(n - 1):
        # Parameter along the line
        t = i / (n - 1)

        # Interpolate color through gradient stops
        num_stops = len(colors)
        segment = t * (num_stops - 1)
        idx = int(segment)
        frac = segment - idx
        if idx >= num_stops - 1:
            idx = num_stops - 2
            frac = 1.0

        r = int(colors[idx][0] + frac * (colors[idx + 1][0] - colors[idx][0]))
        g = int(colors[idx][1] + frac * (colors[idx + 1][1] - colors[idx][1]))
        b = int(colors[idx][2] + frac * (colors[idx + 1][2] - colors[idx][2]))

        color = (r, g, b, 255)
        draw.line([points[i], points[i + 1]], fill=color, width=line_width)


def draw_glow_line(img, points, colors, line_width, glow_radius=8, glow_intensity=0.6):
    """
    Draw glow effect behind the line.
    """
    # Create glow layer
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)

    # Draw thicker line for glow base
    glow_width = line_width + glow_radius * 2
    draw_gradient_line(glow_draw, points, colors, glow_width, img.size)

    # Blur it
    glow = glow.filter(ImageFilter.GaussianBlur(radius=glow_radius))

    # Reduce intensity
    glow_data = glow.split()
    alpha = glow_data[3].point(lambda p: int(p * glow_intensity))
    glow.putalpha(alpha)

    # Composite glow under
    img.paste(Image.alpha_composite(
        Image.new("RGBA", img.size, (0, 0, 0, 0)),
        glow
    ), (0, 0), glow)

    return img


# ----------- STATUS BAR ICON (36x36 template) -----------

def create_status_bar_icon():
    """
    Create 36x36 white waveform on transparent background.
    macOS template image — white stroke only, alpha channel matters.
    """
    size = 36
    scale = 4  # Render at 4x for anti-aliasing
    render_size = size * scale

    img = Image.new("RGBA", (render_size, render_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Generate waveform points — for small icon, use fewer oscillations
    points = []
    num_points = 300
    margin_x = 0.10
    margin_y = 0.25

    for i in range(num_points + 1):
        t = i / num_points
        x = margin_x * render_size + t * (1 - 2 * margin_x) * render_size

        # D-shaped envelope
        center = 0.55
        w_left = 0.25
        w_right = 0.20
        if t < center:
            dist = (t - center) / w_left
        else:
            dist = (t - center) / w_right
        envelope = math.exp(-0.5 * dist * dist)
        envelope = max(envelope, 0.04)

        # Fewer cycles for readability at small size
        freq = 10
        wave = math.sin(2 * math.pi * freq * t)
        wave += 0.25 * math.sin(2 * math.pi * freq * 2.0 * t)
        wave /= 1.25

        y_norm = envelope * wave
        y = render_size / 2 - y_norm * (0.5 - margin_y) * render_size
        points.append((x, y))

    # Draw white line
    line_width = max(2, int(scale * 1.8))
    white = (255, 255, 255, 255)
    for i in range(len(points) - 1):
        draw.line([points[i], points[i + 1]], fill=white, width=line_width)

    # Downscale with anti-aliasing
    img = img.resize((size, size), Image.LANCZOS)

    output_path = os.path.join(RESOURCES_DIR, "StatusBarIcon@2x.png")
    img.save(output_path, "PNG")
    print(f"  StatusBarIcon@2x.png -> {output_path} ({size}x{size})")
    return output_path


# ----------- APP ICON (multiple sizes) -----------

def create_app_icon_at_size(target_size):
    """
    Create app icon at the given pixel size.
    Dark background with purple gradient pulse and glow.
    """
    # Render at higher resolution for quality, then downscale
    if target_size <= 32:
        scale = 8
    elif target_size <= 64:
        scale = 6
    elif target_size <= 128:
        scale = 4
    else:
        scale = 2

    render_size = target_size * scale

    # Dark background gradient (top-left to bottom-right)
    bg_top = (8, 5, 15)      # #08050f
    bg_bottom = (14, 9, 25)   # #0e0919

    # IMPORTANT: macOS dock requires fully OPAQUE background (no transparency)
    # Any transparent pixel shows as WHITE in dock
    img = Image.new("RGB", (render_size, render_size), bg_top)
    draw = ImageDraw.Draw(img)

    # Draw background gradient (RGB, no alpha)
    for y in range(render_size):
        t = y / render_size
        r = int(bg_top[0] + t * (bg_bottom[0] - bg_top[0]))
        g = int(bg_top[1] + t * (bg_bottom[1] - bg_top[1]))
        b = int(bg_top[2] + t * (bg_bottom[2] - bg_top[2]))
        draw.line([(0, y), (render_size, y)], fill=(r, g, b))

    # Subtle radial vignette (darker edges) — baked into RGB
    cx, cy = render_size / 2, render_size / 2
    max_dist = math.sqrt(cx * cx + cy * cy)
    for y in range(0, render_size, max(1, scale * 2)):
        for x in range(0, render_size, max(1, scale * 2)):
            dist = math.sqrt((x - cx) ** 2 + (y - cy) ** 2) / max_dist
            darken = min(40, int(dist * 60))
            if darken > 0:
                px = img.getpixel((x, y))
                new_px = (max(0, px[0] - darken), max(0, px[1] - darken), max(0, px[2] - darken))
                draw.rectangle([x, y, x + scale * 2, y + scale * 2], fill=new_px)

    # Convert to RGBA for compositing glow layers, but keep alpha=255
    img = img.convert("RGBA")

    # Generate waveform points
    num_points = 600
    margin_x = 0.12
    margin_y = 0.22

    # Adjust for very small icons
    if target_size <= 32:
        margin_x = 0.08
        margin_y = 0.28

    points = []
    for i in range(num_points + 1):
        t = i / num_points
        x = margin_x * render_size + t * (1 - 2 * margin_x) * render_size

        # D-shaped envelope
        center = 0.55
        w_left = 0.22
        w_right = 0.18
        if t < center:
            dist_t = (t - center) / w_left
        else:
            dist_t = (t - center) / w_right
        envelope = math.exp(-0.5 * dist_t * dist_t)
        envelope = max(envelope, 0.05)

        # Oscillation
        if target_size <= 32:
            freq = 8  # Fewer cycles for tiny icons
        elif target_size <= 64:
            freq = 10
        else:
            freq = 14

        wave = math.sin(2 * math.pi * freq * t)
        wave += 0.3 * math.sin(2 * math.pi * freq * 2.1 * t)
        wave /= 1.3

        y_norm = envelope * wave
        y = render_size / 2 - y_norm * (0.5 - margin_y) * render_size
        points.append((x, y))

    # Purple gradient colors
    colors = [
        (139, 35, 229),   # #8B23E5
        (160, 55, 240),   # mid
        (180, 74, 255),   # #b44aff
        (212, 160, 255),  # #d4a0ff
        (180, 74, 255),   # #b44aff back
        (139, 35, 229),   # #8B23E5
    ]

    # Line width scales with size
    if target_size <= 32:
        base_width = 2.5
        glow_r = 6
    elif target_size <= 64:
        base_width = 3.0
        glow_r = 8
    elif target_size <= 128:
        base_width = 3.5
        glow_r = 10
    else:
        base_width = 4.0
        glow_r = 14

    line_width = max(2, int(base_width * scale))
    glow_radius = int(glow_r * scale)

    # Draw outer glow (bigger, more diffuse)
    img = draw_glow_line(img, points, colors, line_width,
                         glow_radius=glow_radius, glow_intensity=0.35)

    # Draw inner glow (tighter)
    img = draw_glow_line(img, points, colors, line_width,
                         glow_radius=int(glow_radius * 0.4), glow_intensity=0.5)

    # Draw the main line
    line_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    line_draw = ImageDraw.Draw(line_layer)
    draw_gradient_line(line_draw, points, colors, line_width, img.size)
    img = Image.alpha_composite(img, line_layer)

    # Draw bright center (thinner, lighter line for "glow core" effect)
    core_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    core_draw = ImageDraw.Draw(core_layer)
    core_colors = [
        (200, 150, 255),
        (220, 180, 255),
        (240, 210, 255),
        (255, 235, 255),
        (240, 210, 255),
        (200, 150, 255),
    ]
    core_width = max(1, line_width // 3)
    draw_gradient_line(core_draw, points, core_colors, core_width, img.size)
    # Reduce opacity of core
    core_data = core_layer.split()
    alpha = core_data[3].point(lambda p: int(p * 0.6))
    core_layer.putalpha(alpha)
    img = Image.alpha_composite(img, core_layer)

    # Downscale with high-quality resampling
    img = img.resize((target_size, target_size), Image.LANCZOS)

    # Flatten to RGB then back to RGBA with full opacity
    # This ensures NO transparent pixels that macOS dock would show as white
    flat = Image.new("RGB", img.size, (8, 5, 15))
    flat.paste(img, mask=img.split()[3])
    result = flat.convert("RGBA")

    return result


def create_all_app_icons():
    """
    Generate all required sizes and create .icns using iconutil.
    """
    iconset_dir = "/tmp/AppIcon.iconset"
    os.makedirs(iconset_dir, exist_ok=True)

    # Required sizes for iconutil
    icon_specs = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    # Cache rendered sizes to avoid re-rendering same size
    size_cache = {}

    for filename, size in icon_specs:
        if size not in size_cache:
            print(f"  Rendering {size}x{size}...")
            size_cache[size] = create_app_icon_at_size(size)

        output_path = os.path.join(iconset_dir, filename)
        size_cache[size].save(output_path, "PNG")
        print(f"  {filename} -> {output_path}")

    # Also save a 512x512 PNG for fallback
    fallback_path = os.path.join(RESOURCES_DIR, "AppIcon.png")
    size_cache[512].save(fallback_path, "PNG")
    print(f"  AppIcon.png -> {fallback_path}")

    # Create .icns
    icns_path = os.path.join(RESOURCES_DIR, "AppIcon.icns")
    result = subprocess.run(
        ["iconutil", "-c", "icns", iconset_dir, "-o", icns_path],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"  ERROR: iconutil failed: {result.stderr}")
        return None
    else:
        print(f"  AppIcon.icns -> {icns_path}")
        return icns_path


# ----------- MAIN -----------

if __name__ == "__main__":
    print("=== Pulse Icon Generator ===\n")

    print("[1/2] Status Bar Icon (36x36 template)...")
    create_status_bar_icon()

    print("\n[2/2] App Icon (all sizes + .icns)...")
    create_all_app_icons()

    print("\nDone!")
