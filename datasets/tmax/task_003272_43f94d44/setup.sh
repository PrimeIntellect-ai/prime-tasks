#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/assets

    cat << 'EOF' > /home/user/assets/chassis.gcode
G21 ; Set units to millimeters
G90 ; Use absolute coordinates
G1 X10.0 Y15.0 Z0.2
G1 X120.5 Y15.0 Z0.2
G1 X120.5 Y110.0 Z5.5
G1 X10.0 Y110.0 Z12.4
G0 X0.0 Y0.0 Z15.0
EOF

    cat << 'EOF' > /home/user/dummy.c
int main() { return 0; }
EOF
    gcc /home/user/dummy.c -o /home/user/assets/firmware.elf
    rm /home/user/dummy.c

    python3 -c '
with open("/home/user/draft.md", "w") as f:
    f.write("# Robotics Documentation\n\n")
    f.write("## Chassis Manufacturing\n")
    f.write("The chassis is 3D printed.\n")
    f.write("Bounding Box: {" + "{GCODE_STATS:assets/chassis.gcode}" + "}\n\n")
    f.write("## Firmware\n")
    f.write("The main control firmware is a 64-bit ELF executable.\n")
    f.write("Memory location: {" + "{ELF_ENTRY:assets/firmware.elf}" + "}\n\n")
    f.write("End of document.\n")
'

    chmod -R 777 /home/user
