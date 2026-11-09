#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/simulate_allele.sh
#!/bin/bash
m=$1
dt=$2
if [ -z "$m" ]; then m=1.0; fi
if [ -z "$dt" ]; then dt=0.5; fi
awk -v m="$m" -v dt="$dt" 'BEGIN {
    w = 0.99
    b = 2.0
    t = 0
    while (t < 10) {
        dw = -m * w + b * w * (1 - w)
        w = w + dw * dt
        t = t + dt
    }
    printf "%.6f\n", w
}'
EOF
    chmod +x /home/user/simulate_allele.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
