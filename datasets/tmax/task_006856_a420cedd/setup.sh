#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils tar gzip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project_setup/bin
    mkdir -p /home/user/project_setup/logs
    mkdir -p /home/user/project_setup/nested_dir
    mkdir -p /home/user/project_setup/nested_dir/inner_bin

    # Create dummy non-ELF files
    echo "log data" > /home/user/project_setup/logs/app.log
    echo "G1 X10 Y10" > /home/user/project_setup/shape1.gcode
    echo "G1 Z5" > /home/user/project_setup/nested_dir/shape2.gcode
    echo "text file" > /home/user/project_setup/readme.txt

    # Copy real ELF files to act as binaries
    cp /bin/ls /home/user/project_setup/bin/tool_ls
    cp /bin/cat /home/user/project_setup/bin/tool_cat
    cp /bin/echo /home/user/project_setup/nested_dir/inner_bin/tool_echo

    # Create the nested archive
    cd /home/user/project_setup/nested_dir
    tar -cf inner_backup.tar inner_bin shape2.gcode
    rm -rf inner_bin shape2.gcode

    # Create the main archive
    cd /home/user/project_setup
    tar -czf /home/user/project_backups.tar.gz *

    # Cleanup setup dir
    rm -rf /home/user/project_setup

    chmod -R 777 /home/user
