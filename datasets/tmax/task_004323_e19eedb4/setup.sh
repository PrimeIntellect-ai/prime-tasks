#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/dataset_archive/exp_A/run_1
    mkdir -p /home/user/dataset_archive/exp_B/run_2

    cat << 'EOF' > /home/user/dataset_archive/exp_A/run_1/sys.log
INFO: Startup
ERROR: CORRUPT_RECORD ID=105 MSG=Bad_CRC [2023-10-01T10:15:00Z]
WARN: Low memory
ERROR: CORRUPT_RECORD ID=002 MSG=Null_Pointer [2023-10-01T10:16:22Z]
EOF

    cat << 'EOF' > /home/user/dataset_archive/exp_B/run_2/sys.log
INFO: Processing
ERROR: CORRUPT_RECORD ID=042 MSG=Timeout [2023-10-02T08:00:00Z]
INFO: Shutdown
EOF

    printf "\x11\x22\x33\x44\x55\x66\x77\x88\x99\xAA" > /home/user/dataset_archive/exp_A/run_1/sensor.dat
    printf "\xAA\xBB\xCC\xDD\xEE\xFF\x00\x11\x22\x33" > /home/user/dataset_archive/exp_A/run_1/image.dat
    printf "\xDE\xAD\xBE\xEF\x00\x00\x00\x00" > /home/user/dataset_archive/exp_B/run_2/audio.dat
    printf "\x01\x02\x03\x04\x05\x06\x07\x08" > /home/user/dataset_archive/exp_B/run_2/valid.dat

    echo "0102030405060708" > /home/user/dataset_archive/exp_B/run_2/valid.meta

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
