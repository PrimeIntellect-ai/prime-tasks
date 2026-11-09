#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/legacy /home/user/mock_proc /home/user/py_telemetry

    cat << 'EOF' > /home/user/legacy/math_ops.c
double calculate_score(double load1, double load5, double load15, long mem_total, long mem_free) {
    double load_avg = (load1 + load5 + load15) / 3.0;
    double mem_ratio = (double)mem_free / (double)mem_total;
    return (100.0 - (load_avg * 10.0)) * mem_ratio;
}
EOF

    cat << 'EOF' > /home/user/legacy/telemetry.sh
#!/bin/bash
# Legacy script for reference - agent does not need to run this
LOAD=$(cat /home/user/mock_proc/loadavg | awk '{print $1, $2, $3}')
MEMTOT=$(grep MemTotal /home/user/mock_proc/meminfo | awk '{print $2}')
MEMFREE=$(grep MemFree /home/user/mock_proc/meminfo | awk '{print $2}')
# ./math_ops $LOAD $MEMTOT $MEMFREE
EOF

    cat << 'EOF' > /home/user/mock_proc/loadavg
2.50 3.00 3.50 2/250 5678
EOF

    cat << 'EOF' > /home/user/mock_proc/meminfo
MemTotal:       16384000 kB
MemFree:         4096000 kB
MemAvailable:    8192000 kB
Buffers:          123456 kB
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
