#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr fonts-dejavu-core
    pip3 install pytest Pillow

    mkdir -p /app
    mkdir -p /home/user

    # Create oracle script
    cat << 'EOF' > /app/oracle_route_filter
#!/usr/bin/env python3
import sys
import ipaddress

def main():
    if len(sys.argv) != 2:
        sys.exit(1)

    target_ip_str = sys.argv[1]
    try:
        target_ip = ipaddress.IPv4Address(target_ip_str)
    except:
        print("DROP")
        return

    best_match = None
    best_prefix = -1

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) != 2:
            continue
        cidr_str, nexthop = parts
        try:
            network = ipaddress.IPv4Network(cidr_str, strict=False)
        except:
            continue

        if target_ip in network:
            if network.prefixlen > best_prefix:
                best_prefix = network.prefixlen
                best_match = nexthop

    if best_match:
        print(best_match)
    else:
        print("DROP")

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle_route_filter

    # Generate video with Pillow and ffmpeg
    cat << 'EOF' > /tmp/gen_video.py
from PIL import Image, ImageDraw, ImageFont
import subprocess
import os

os.makedirs("/tmp/frames", exist_ok=True)
ips = {
    45: "10.5.2.11",
    112: "172.16.8.99",
    198: "192.168.100.4",
    250: "192.168.100.5"
}

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 24)
except:
    font = ImageFont.load_default()

for i in range(1, 301):
    img = Image.new('RGB', (640, 480), color='black')
    d = ImageDraw.Draw(img)
    text = f"System log... frame {i}"
    if i in ips:
        text += f"\nCRITICAL_DROP: {ips[i]}"
    d.text((10,10), text, fill=(255,255,255), font=font)
    img.save(f"/tmp/frames/frame_{i:03d}.png")

subprocess.run([
    "ffmpeg", "-y", "-framerate", "30", "-i", "/tmp/frames/frame_%03d.png",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "/app/tunnel_monitor.mp4"
], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
EOF
    python3 /tmp/gen_video.py
    rm -rf /tmp/frames /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
