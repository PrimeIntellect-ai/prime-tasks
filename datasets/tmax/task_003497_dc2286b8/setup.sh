#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils coreutils grep sed gawk
    pip3 install pytest

    mkdir -p /home/user/incoming
    mkdir -p /home/user/repo

    # Copy system binaries to act as incoming artifacts
    cp /bin/ls /home/user/incoming/ls_bin
    cp /bin/cp /home/user/incoming/cp_bin
    cp /lib/x86_64-linux-gnu/libc.so.6 /home/user/incoming/libc_lib.so
    cp /lib/x86_64-linux-gnu/libm.so.6 /home/user/incoming/libm_lib.so

    # Create junk files
    echo "This is a text file, not an ELF." > /home/user/incoming/readme.txt
    printf "#!/bin/bash\necho 'hello'\n" > /home/user/incoming/script.sh
    chmod +x /home/user/incoming/script.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
