#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest

    mkdir -p /home/user/monitor

    cat << 'EOF' > /home/user/monitor/latencies.txt
100000000.001
100000000.005
100000000.002
100000000.008
100000000.004
100000000.006
EOF

    cat << 'EOF' > /home/user/monitor/calc_stats.sh
#!/bin/bash
input_file=$1

awk '
{
    n++
    sum += $1
    sum_sq += $1 * $1
}
END {
    if (n > 1) {
        mean = sum / n
        var = (sum_sq - (sum * sum)/n) / (n - 1)
        printf "Mean: %.3f\n", mean
        printf "StdDev: %.3f\n", sqrt(var)
    } else {
        print "Not enough data"
    }
}' "$input_file"
EOF

    chmod +x /home/user/monitor/calc_stats.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
