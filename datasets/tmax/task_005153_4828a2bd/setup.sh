#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest SpeechRecognition

    mkdir -p /app/backup_recovery/tangled_fs
    mkdir -p /app/.hidden

    # Generate the audio file
    espeak -w /app/backup_recovery/voicenote.wav "Please extract only data for tool T2, binaries compiled for ARM architecture, and transaction IDs greater than 500."

    # Generate the filesystem and ground truth using Python
    python3 -c "
import os
import gzip
import zipfile
import struct
import json

base_dir = '/app/backup_recovery/tangled_fs'
os.makedirs(os.path.join(base_dir, 'dirA'), exist_ok=True)
os.makedirs(os.path.join(base_dir, 'dirB'), exist_ok=True)

# Create symlink loops
os.symlink('../dirB', os.path.join(base_dir, 'dirA/link'))
os.symlink('../dirA', os.path.join(base_dir, 'dirB/link'))

# GCode file
gcode_path = os.path.join(base_dir, 'dirA/file1.gcode.gz')
gcode_content = b'T2\nG1 X10 Y10 E5.0\nT1\nG1 X20 Y20 E3.0\nT2\nG1 X30 Y30 E2.5\n'
with gzip.open(gcode_path, 'wb') as f:
    f.write(gcode_content)

# ELF ARM file
elf_path = os.path.join(base_dir, 'dirB/file2.elf.zip')
elf_arm = b'\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00' + b'\x00'*40
with zipfile.ZipFile(elf_path, 'w') as z:
    z.writestr('file2.elf', elf_arm)

# WAL file
wal_path = os.path.join(base_dir, 'dirA/file3.wal.gz')
# Magic: 0x57414C00 (Little Endian)
wal_content = struct.pack('<I', 0x57414C00)
# Records: ID, Length, Payload
wal_content += struct.pack('<IH2s', 400, 2, b'ab')
wal_content += struct.pack('<IH2s', 505, 2, b'cd')
wal_content += struct.pack('<IH2s', 600, 2, b'ef')
with gzip.open(wal_path, 'wb') as f:
    f.write(wal_content)

# Ground truth
ground_truth = {
    os.path.abspath(gcode_path): 7.5,
    os.path.abspath(elf_path): True,
    os.path.abspath(wal_path): 2
}

with open('/app/.hidden/ground_truth.json', 'w') as f:
    json.dump(ground_truth, f)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
