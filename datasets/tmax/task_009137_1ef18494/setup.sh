#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming
    mkdir -p /home/user/repo

    create_artifact() {
        local id=$1
        local date=$2
        local filename="/home/user/incoming/artifact_${id}.tar.gz"

        mkdir -p /tmp/artifact_gen
        echo "Build-ID: ${id}" > /tmp/artifact_gen/metadata.txt
        echo "Date: ${date}" >> /tmp/artifact_gen/metadata.txt
        echo "Author: System" >> /tmp/artifact_gen/metadata.txt

        dd if=/dev/urandom of=/tmp/artifact_gen/payload.bin bs=1K count=1 2>/dev/null

        tar -czf "${filename}" -C /tmp/artifact_gen metadata.txt payload.bin
        rm -rf /tmp/artifact_gen
    }

    create_artifact "B101" "2023-10-01"
    create_artifact "B102" "2023-10-02"
    create_artifact "B103" "2023-11-05"
    create_artifact "B104" "2024-01-15"
    create_artifact "B105" "2024-02-28"

    echo "[]" > /home/user/repo/manifest.json

    chmod -R 777 /home/user
