#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming
    mkdir -p /home/user/safe_artifacts
    mkdir -p /home/user/quarantine

    python3 -c '
import tarfile
import io

with tarfile.open("/home/user/incoming/artifacts.tar", "w") as tar:
    # 0: Safe
    info1 = tarfile.TarInfo(name="safe1.bin")
    data1 = b"safe data 1\n"
    info1.size = len(data1)
    tar.addfile(info1, io.BytesIO(data1))

    # 1: Malicious (Zip Slip)
    info2 = tarfile.TarInfo(name="../escape.bin")
    data2 = b"malicious data A\n"
    info2.size = len(data2)
    tar.addfile(info2, io.BytesIO(data2))

    # 2: Safe
    info3 = tarfile.TarInfo(name="safe2.bin")
    data3 = b"safe data 2\n"
    info3.size = len(data3)
    tar.addfile(info3, io.BytesIO(data3))

    # 3: Malicious (Absolute Path)
    info4 = tarfile.TarInfo(name="/etc/fake_shadow")
    data4 = b"malicious data B\n"
    info4.size = len(data4)
    tar.addfile(info4, io.BytesIO(data4))
'

    chmod -R 777 /home/user
