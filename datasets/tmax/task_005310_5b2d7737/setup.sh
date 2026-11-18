#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user/artifacts

    # File 1: Valid, matches all criteria
    printf '\x41\x52\x54\x46\x0A\x00\x00\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A' > /home/user/artifacts/alpha.bin
    touch -d "1 day ago" /home/user/artifacts/alpha.bin

    # File 2: Invalid magic, matches all criteria
    printf '\x42\x41\x44\x44\x0A\x00\x00\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A' > /home/user/artifacts/beta.bin
    touch -d "2 days ago" /home/user/artifacts/beta.bin

    # File 3: Valid, but too old (modified 10 days ago)
    printf '\x41\x52\x54\x46\x0A\x00\x00\x00\xAA\xBB\xCC\xDD\xEE\xFF\x00\x11\x22\x33' > /home/user/artifacts/gamma.bin
    touch -d "10 days ago" /home/user/artifacts/gamma.bin

    # File 4: Valid, but too small (size <= 15 bytes)
    printf '\x41\x52\x54\x46\x02\x00\x00\x00\x99\x88' > /home/user/artifacts/delta.bin
    touch -d "1 day ago" /home/user/artifacts/delta.bin

    # File 5: Incomplete payload, matches metadata criteria
    printf '\x41\x52\x54\x46\x14\x00\x00\x00\x11\x22\x33\x44\x55' > /home/user/artifacts/epsilon.bin
    printf '\x00\x00\x00' >> /home/user/artifacts/epsilon.bin
    touch -d "12 hours ago" /home/user/artifacts/epsilon.bin

    # File 6: Valid, matches criteria
    printf '\x41\x52\x54\x46\x08\x00\x00\x00\xDE\xAD\xBE\xEF\xCA\xFE\xBA\xBE' > /home/user/artifacts/zeta.bin
    touch -d "now" /home/user/artifacts/zeta.bin

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/artifacts
    chmod -R 777 /home/user
