#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip strace netcat-openbsd gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pipeline
    cd /home/user/pipeline

    cat << 'EOF' > data.txt
100000000.001
100000000.002
100000000.003
100000000.004
100000000.005
EOF

    cat << 'EOF' > metrics_server.sh
#!/bin/bash
rm -f metrics.log
while true; do
    # Listen for a single line from nc and append to log with a timestamp
    res=$(nc -l -p 9090 -q 0)
    if [ ! -z "$res" ]; then
        echo "$(date +'%H:%M:%S.%N') - $res" >> metrics.log
    fi
done
EOF
    chmod +x metrics_server.sh

    cat << 'EOF' > worker.sh
#!/bin/bash
sum_x=0
sum_x2=0
N=0
while read -r x; do
    sum_x=$(awk "BEGIN {print $sum_x + $x}")
    sum_x2=$(awk "BEGIN {printf \"%.10f\", $sum_x2 + ($x * $x)}")
    N=$((N+1))
    echo "processed $N" | nc -w 1 localhost 9090
done < /home/user/pipeline/data.txt

# Naive standard deviation (causes fatal error due to negative variance from float precision issues)
stddev=$(awk "BEGIN { variance = ($sum_x2 - ($sum_x * $sum_x)/$N)/$N; print sqrt(variance) }")
echo $stddev > /home/user/pipeline/result.txt
EOF
    chmod +x worker.sh

    chmod -R 777 /home/user
