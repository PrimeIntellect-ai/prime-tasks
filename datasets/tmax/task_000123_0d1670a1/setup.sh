#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gawk sed coreutils findutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_repo/bin /home/user/raw_repo/scripts /home/user/raw_repo/data

    # 1. Valid ELF, executable, > 50KB -> Should be in output
    dd if=/dev/zero of=/home/user/raw_repo/bin/service_worker bs=1024 count=60 2>/dev/null
    printf '\177ELF' | dd of=/home/user/raw_repo/bin/service_worker bs=1 seek=0 conv=notrunc 2>/dev/null

    # 2. Valid ELF, executable, > 50KB -> Should be in output
    dd if=/dev/zero of=/home/user/raw_repo/bin/backend_api bs=1024 count=80 2>/dev/null
    printf '\177ELF' | dd of=/home/user/raw_repo/bin/backend_api bs=1 seek=0 conv=notrunc 2>/dev/null

    # 3. Not an ELF (script), executable, > 50KB -> Filtered by C++
    dd if=/dev/zero of=/home/user/raw_repo/scripts/startup.sh bs=1024 count=55 2>/dev/null
    printf "#!/bin/bash\n" | dd of=/home/user/raw_repo/scripts/startup.sh bs=1 seek=0 conv=notrunc 2>/dev/null

    # 4. Valid ELF, NOT executable, > 50KB -> Filtered by find
    dd if=/dev/zero of=/home/user/raw_repo/data/libcore.so bs=1024 count=70 2>/dev/null
    printf '\177ELF' | dd of=/home/user/raw_repo/data/libcore.so bs=1 seek=0 conv=notrunc 2>/dev/null

    # 5. Valid ELF, executable, < 50KB -> Filtered by find
    dd if=/dev/zero of=/home/user/raw_repo/bin/tiny_tool bs=1024 count=20 2>/dev/null
    printf '\177ELF' | dd of=/home/user/raw_repo/bin/tiny_tool bs=1 seek=0 conv=notrunc 2>/dev/null

    chmod -R 777 /home/user
    chmod u-x /home/user/raw_repo/data/libcore.so
