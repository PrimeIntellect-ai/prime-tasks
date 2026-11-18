#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os

os.makedirs("/home/user/project_files/builds/v1", exist_ok=True)
os.makedirs("/home/user/project_files/builds/v2", exist_ok=True)
os.makedirs("/home/user/project_files/models", exist_ok=True)
os.makedirs("/home/user/project_files/logs", exist_ok=True)

with open("/home/user/project_files/builds/v1/firmware_v1.bin", "wb") as f:
    f.write(b"\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00")

with open("/home/user/project_files/builds/v2/fw_v2_final.out", "wb") as f:
    f.write(b"\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00")

with open("/home/user/project_files/models/bracket.gcode", "wb") as f:
    f.write(b"; Slic3r generated\nG1 X10 Y20 Z0.2\nM104 S200\n")

with open("/home/user/project_files/models/gear.gcode", "wb") as f:
    f.write(b"G0 X0 Y0 F3000\nG1 Z5\n")

with open("/home/user/project_files/models/notes.gcode", "wb") as f:
    f.write(b"This is just a text file\n")

with open("/home/user/project_files/logs/build.log", "wb") as f:
    f.write(b"Random text data here\n")

with open("/home/user/project_files/builds/v1/dump.dat", "wb") as f:
    f.write(b"\x00\x01\x02\x03\x04")
'

    chown -R user:user /home/user/project_files
    chmod -R 777 /home/user
