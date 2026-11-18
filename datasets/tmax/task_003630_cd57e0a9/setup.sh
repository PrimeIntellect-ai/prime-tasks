#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak build-essential binutils
pip3 install pytest

mkdir -p /app
mkdir -p /home/user

# Generate audio file
espeak -w /tmp/speech.wav "The dataset offset begins at byte forty four thousand one hundred."

# Pad to exactly 44100 bytes
python3 -c "
import os
with open('/tmp/speech.wav', 'rb') as f:
    data = f.read()
if len(data) < 44100:
    data += b'\0' * (44100 - len(data))
else:
    data = data[:44100]
with open('/app/dataset_record.wav', 'wb') as f:
    f.write(data)
"

# Create dummy ELF
echo 'int main(){return 0;}' > /tmp/dummy.cpp
g++ /tmp/dummy.cpp -o /tmp/dummy.elf

# Create GCode
cat << 'EOF' > /tmp/dataset.gcode
G1 X10.0 Y0.0
G1 X10.0 Y10.0
G1 X0.0 Y10.0
G1 X0.0 Y0.0
EOF

# Add section to ELF
objcopy --add-section .gcode=/tmp/dataset.gcode /tmp/dummy.elf /tmp/embedded.elf

# Append ELF to WAV
cat /tmp/embedded.elf >> /app/dataset_record.wav

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
