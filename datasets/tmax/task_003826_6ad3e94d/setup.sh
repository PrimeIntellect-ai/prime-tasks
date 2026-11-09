#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip bc
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/metrics.csv
timestamp,cpu_usage,mem_usage
1001,45.5,1024
1002,48.2,1050
1003,99.9,2048
1004,85.1,1900
EOF

cat << 'EOF' > /home/user/aggregate.sh
#!/bin/bash
# Calculates average CPU and Memory usage

exec < /home/user/metrics.csv
read header

total_cpu=0
total_mem=0
count=0

while read -r line; do
    if [ -z "$line" ]; then continue; fi

    cleaned=0
    while [ $cleaned -eq 0 ]; do
        cpu=$(echo "$line" | cut -d',' -f2)
        mem=$(echo "$line" | cut -d',' -f3)

        if [[ "$cpu" == "99.9" ]]; then
            cpu=100.0
            # BUG 1: missing cleaned=1 here causes infinite loop because cpu is re-read from line next iteration
        else
            cleaned=1
        fi
    done

    total_cpu=$(echo "$total_cpu + $cpu" | bc)
    total_mem=$(echo "$total_mem + $mem" | bc)
    count=$((count + 1))
done

# BUG 2 & 3: Precision loss in averaging formulas
avg_cpu=$(( total_cpu / count ))
avg_mem=$(echo "$total_mem / $count" | bc)

echo "AvgCPU: $avg_cpu" > /home/user/results.txt
echo "AvgMem: $avg_mem" >> /home/user/results.txt
EOF

chmod +x /home/user/aggregate.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
