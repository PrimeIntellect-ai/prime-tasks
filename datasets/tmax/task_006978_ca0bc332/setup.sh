#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar gzip binutils gawk sed
    pip3 install pytest

    mkdir -p /home/user/dataset_raw
    cd /home/user/dataset_raw

    # Create GCode files
    cat << 'EOF' > print_alpha.gcode
G28 ; Home
G1 X10 Y10 Z0.2 F1200
G1 X20 Y20 Z1.5
G0 Z15.2 F3000
G1 X0 Y0
EOF

    cat << 'EOF' > print_beta.gcode
G28
G0 X0 Y0 Z0.3
G1 X5 Y5 Z5.5
G1 X10 Y10 Z4.2
EOF

    # Create ELF files
    cp /bin/ls ./firmware_v1.elf
    cp /bin/bash ./controller.elf

    # Get the actual Machine string for the golden output
    MACH_LS=$(readelf -h ./firmware_v1.elf | grep "Machine:" | awk -F': ' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
    MACH_BASH=$(readelf -h ./controller.elf | grep "Machine:" | awk -F': ' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')

    # Pack into nested archives
    tar -czvf dataset.tar.gz *.gcode *.elf
    zip /home/user/raw_data.zip dataset.tar.gz

    # Clean up raw directory
    cd /home/user
    rm -rf /home/user/dataset_raw

    # Create the expected output file for verification
    cat << EOF > /home/user/expected_summary.csv
filename,type,metadata
controller.elf,ELF,$MACH_BASH
firmware_v1.elf,ELF,$MACH_LS
print_alpha.gcode,GCode,15.2
print_beta.gcode,GCode,5.5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
