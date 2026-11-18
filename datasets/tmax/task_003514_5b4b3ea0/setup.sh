#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar bzip2 gzip coreutils
    pip3 install pytest

    mkdir -p /home/user/research_data
    cd /home/user/research_data

    # Create binary files
    mkdir -p sensors_tmp
    dd if=/dev/urandom of=sensors_tmp/bin_143211.dat bs=1K count=1 2>/dev/null
    dd if=/dev/urandom of=sensors_tmp/bin_143500.dat bs=1K count=1 2>/dev/null
    dd if=/dev/urandom of=sensors_tmp/bin_144000.dat bs=1K count=1 2>/dev/null
    dd if=/dev/urandom of=sensors_tmp/bin_144500.dat bs=1K count=1 2>/dev/null

    # Create logs
    mkdir -p logs_tmp
    cat << 'EOF' > logs_tmp/experiment.log
Timestamp: 2023-10-05 14:32:11
Event: ThermalCalibration
Status: SUCCESS
DataFile: bin_143211.dat
--
Timestamp: 2023-10-05 14:35:00
Event: CoreOverload
Status: ERROR
Error_Code: 0x88B
DataFile: bin_143500.dat
--
Timestamp: 2023-10-05 14:40:00
Event: RoutineCheck
Status: SUCCESS
DataFile: bin_144000.dat
--
Timestamp: 2023-10-05 14:45:00
Event: MemoryLeak
Status: ERROR
Error_Code: 0x11A
DataFile: bin_144500.dat
--
EOF

    # Package archives
    cd sensors_tmp
    tar -cjf ../sensors.tar.bz2 *
    cd ../logs_tmp
    tar -czf ../logs.tar.gz *
    cd ..
    tar -cf master_dataset.tar logs.tar.gz sensors.tar.bz2

    # Cleanup
    rm -rf sensors_tmp logs_tmp sensors.tar.bz2 logs.tar.gz

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
