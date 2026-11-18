#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/storage
mkdir -p /home/user/extracted_gcode

cat << 'EOF' > /home/user/setup_log.py
import binascii

def compress_rle(text):
    if not text:
        return ""
    encoded = ""
    i = 0
    while i < len(text):
        count = 1
        while i + 1 < len(text) and text[i] == text[i+1] and count < 255:
            count += 1
            i += 1
        encoded += f"{count:02x}{ord(text[i]):02x}"
        i += 1
    return encoded

def chunk_string(string, length):
    return [string[0+i:length+i] for i in range(0, len(string), length)]

gcode_1 = """G21 ; Set units to millimeters
G90 ; Use absolute coordinates
G1 X10 Y10 F1000
G1 Z0.5
G1 E5 F300
"""

gcode_2 = """M104 S200 ; Set extruder temp
M140 S60 ; Set bed temp
G28 ; Home all axes
G1 X100.5 Y100.5 Z10 F2000
"""

log_content = f"""[2023-11-01 08:00:00] INFO Server started.
[2023-11-01 08:01:12] WARNING Disk space running low on /spool.
=== BEGIN ARCHIVED GCODE: part_base.gcode ===
{chr(10).join(chunk_string(compress_rle(gcode_1), 40))}
=== END ARCHIVED GCODE ===
[2023-11-01 08:05:00] INFO Spooling complete.
=== BEGIN ARCHIVED GCODE: heated_bed_init.gcode ===
{chr(10).join(chunk_string(compress_rle(gcode_2), 40))}
=== END ARCHIVED GCODE ===
[2023-11-01 08:10:00] INFO System idle.
"""

with open("/home/user/storage/server.log", "w") as f:
    f.write(log_content)
EOF

python3 /home/user/setup_log.py
rm /home/user/setup_log.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
