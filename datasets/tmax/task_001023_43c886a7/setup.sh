#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar gzip
    pip3 install pytest

    mkdir -p /home/user/datasets/run1_dir
    mkdir -p /home/user/datasets/run2_dir
    mkdir -p /home/user/datasets/run3_dir

    cd /home/user/datasets

    # Create valid gcode files
    echo "G28\nG1 X10 Y10\n;TIME:150\nM104 S0" > run1_dir/part1.gcode
    echo "G28\n;TIME:250\nG1 X20" > run1_dir/part2.gcode

    # Create nested archive
    cd run1_dir
    tar -czf nested.tar.gz part2.gcode
    rm part2.gcode
    cd ..
    zip -r run1.zip run1_dir
    rm -rf run1_dir

    # Create run2 with a valid gcode
    echo ";TIME:300\nG1 Z10" > run2_dir/part3.gcode
    tar -czf run2.tar.gz run2_dir
    rm -rf run2_dir

    # Create run3 with a valid gcode and a corrupted nested archive
    echo ";TIME:400\nG1 E-5" > run3_dir/part4.gcode
    echo "This is not a valid tar file" > run3_dir/sub_corrupt.tar.gz
    zip -r run3.zip run3_dir
    rm -rf run3_dir

    # Create completely corrupted top-level archives
    echo "Corrupted zip file data" > corrupt.zip
    echo "Corrupted tar file data" > corrupt.tar.gz

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
