#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ci_builds/alice
    mkdir -p /home/user/ci_builds/bob
    mkdir -p /home/user/ci_builds/charlie

    # Bob: Under quota (30MB total)
    dd if=/dev/urandom of=/home/user/ci_builds/bob/build.log bs=1M count=10
    dd if=/dev/urandom of=/home/user/ci_builds/bob/app.jar bs=1M count=20
    touch -m -d "2023-01-01" /home/user/ci_builds/bob/build.log
    touch -m -d "2023-01-02" /home/user/ci_builds/bob/app.jar

    # Alice: Over quota (60MB total)
    dd if=/dev/urandom of=/home/user/ci_builds/alice/old_build.o bs=1M count=15
    dd if=/dev/urandom of=/home/user/ci_builds/alice/cache.pyc bs=1M count=15
    dd if=/dev/urandom of=/home/user/ci_builds/alice/main.bin bs=1M count=30
    touch -m -d "2023-01-01" /home/user/ci_builds/alice/old_build.o
    touch -m -d "2023-01-02" /home/user/ci_builds/alice/cache.pyc
    touch -m -d "2023-01-03" /home/user/ci_builds/alice/main.bin

    # Charlie: Over quota (50MB total)
    dd if=/dev/urandom of=/home/user/ci_builds/charlie/lib1.so bs=1M count=25
    dd if=/dev/urandom of=/home/user/ci_builds/charlie/lib2.so bs=1M count=25
    touch -m -d "2023-01-01" /home/user/ci_builds/charlie/lib1.so
    touch -m -d "2023-01-02" /home/user/ci_builds/charlie/lib2.so

    chown -R user:user /home/user/ci_builds
    chmod -R 777 /home/user
