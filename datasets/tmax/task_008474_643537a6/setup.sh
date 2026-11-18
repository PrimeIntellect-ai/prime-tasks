#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/setup_tmp
    cd /home/user/setup_tmp

    # Create files with ISO-8859-1 encoding using bash to ensure echo -e works correctly
    bash -c 'echo -e "#include \"utils.h\"\n// Copyright \xA9 1999\nint main() { OLD_MACRO_XYZ; return 0; }\n" > main.cpp'
    bash -c 'echo -e "#define OLD_MACRO_XYZ int x = 1\n// Funci\xF3n utilitaria\n" > utils.h'
    bash -c 'echo -e "#include \"utils.h\"\n// M\xE1s utilidades\n" > utils.cpp'

    tar -cf /home/user/legacy_project.tar main.cpp utils.h utils.cpp
    cd /home/user
    rm -rf /home/user/setup_tmp

    chmod -R 777 /home/user
