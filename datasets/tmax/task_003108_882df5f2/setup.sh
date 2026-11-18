#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip e2fsprogs tesseract-ocr imagemagick bc gawk fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    # Create ext4 image with deleted file
    dd if=/dev/zero of=/app/build_fs.ext4 bs=1M count=10
    mkfs.ext4 /app/build_fs.ext4
    echo "14.592000" > /tmp/offsets.dat
    debugfs -w -R "write /tmp/offsets.dat offsets.dat" /app/build_fs.ext4
    debugfs -w -R "rm offsets.dat" /app/build_fs.ext4
    rm /tmp/offsets.dat

    # Create specs image
    convert -size 1000x200 xc:white -font DejaVu-Sans -pointsize 14 -fill black \
      -draw "text 10,30 'Rule 1: All numbers must be converted to standard decimal notation (no scientific \'e\' notation in the output).'" \
      -draw "text 10,60 'Rule 2: Every output must be padded or truncated to exactly 6 decimal places (e.g., 5.120000).'" \
      -draw "text 10,90 'Rule 3: If an input string cannot be parsed as a valid number, output exactly \"NaN_ERROR\".'" \
      -draw "text 10,120 'Rule 4: Values greater than 999999.999999 must be clamped to \"999999.999999\".'" \
      /app/specs.png

    # Create oracle script
    cat << 'EOF' > /app/ref_parser
#!/usr/bin/env python3
import sys
offset = 14.592000
for line in sys.stdin:
    line = line.strip()
    try:
        val = float(line)
        res = val + offset
        if res > 999999.999999:
            res = 999999.999999
        print(f"{res:.6f}")
    except ValueError:
        print("NaN_ERROR")
EOF
    chmod +x /app/ref_parser

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
