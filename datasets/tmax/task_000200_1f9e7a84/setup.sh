#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_data.py
with open("/home/user/stream.txt", "w") as f:
    for i in range(1, 1001):
        f.write(f"{100000000 + i}\n")
EOF
    python3 /home/user/generate_data.py

    cat << 'EOF' > /home/user/service.sh
#!/bin/bash
WINDOW=10
declare -a history
count=0

while read -r val; do
    history+=("$val")
    count=$((count + 1))

    if [ "$count" -ge "$WINDOW" ]; then
        sum=0
        sum_sq=0
        start=$((count - WINDOW))

        for (( i=start; i<count; i++ )); do
            v=${history[$i]}
            sum=$(awk "BEGIN {print $sum + $v}")
            sum_sq=$(awk "BEGIN {print $sum_sq + ($v * $v)}")
        done

        mean=$(awk "BEGIN {print $sum / $WINDOW}")
        mean_sq=$(awk "BEGIN {print $mean * $mean}")
        exp_sq=$(awk "BEGIN {print $sum_sq / $WINDOW}")

        variance=$(awk "BEGIN {print $exp_sq - $mean_sq}")
        echo "$variance"
    fi
done < /home/user/stream.txt
EOF
    chmod +x /home/user/service.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
