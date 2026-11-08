#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gzip tar bzip2 zip unzip file
    pip3 install pytest

    mkdir -p /home/user/messy/src /home/user/messy/scripts /home/user/messy/bin_hidden

    # Create an ELF file for app_bin
    echo "int main(){}" | gcc -xc - -o /home/user/messy/src/app_bin

    # Create text files with the macro
    echo -e "#include <stdio.h>\nint main() {\n  OLD_MACRO_XYZ();\n  return 0;\n}" > /home/user/messy/src/main.c
    echo -e "def test():\n    print('OLD_MACRO_XYZ()')" > /home/user/messy/scripts/test.py

    # Copy existing system binaries to act as other ELFs
    cp /bin/echo /home/user/messy/bin_hidden/echo_tool.dat
    cp /bin/ls /home/user/messy/ls_exe

    # Create a gzipped text file containing the macro
    echo "Log entry: OLD_MACRO_XYZ() executed." > /home/user/messy/logs.txt
    gzip /home/user/messy/logs.txt

    # Create the main archive
    cd /home/user/messy
    tar -czf /home/user/messy_project.tar.gz .
    cd /
    rm -rf /home/user/messy

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
