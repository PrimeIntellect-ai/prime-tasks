#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/latencies.txt
3000000000
2500000000
2800000000
3100000000
2900000000
EOF

    cat << 'EOF' > /home/user/process_logs.sh
#!/bin/bash
file=$1
sum_sq=0
count=0
while read -r val; do
    sum_sq=$((sum_sq + val * val))
    if [ "$sum_sq" -lt 0 ]; then
        echo "Assertion failed: sum_sq negative due to overflow" >&2
        exit 1
    fi
    count=$((count + 1))
done < "$file"
rms=$(echo "scale=4; sqrt($sum_sq / $count)" | bc)
echo "$rms"
EOF
    chmod +x /home/user/process_logs.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
