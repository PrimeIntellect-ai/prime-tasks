#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/app_logs

    cat << 'EOF' > /home/user/process.sh
#!/bin/bash

rm -f /home/user/readings.txt

for f in /home/user/app_logs/log_*.txt; do
    while read -r ts level b64; do
        # decode base64
        json=$(echo "$b64" | base64 -d)
        # extract reading
        val=$(echo "$json" | jq -r '.sensor_reading')
        echo "$val" >> /home/user/readings.txt
    done < "$f"
done

# Sum readings - currently loses precision!
awk '{sum+=$1} END {print sum}' /home/user/readings.txt > /home/user/total_sum.txt
EOF
    chmod +x /home/user/process.sh

    python3 -c '
import base64
import os

log_dir = "/home/user/app_logs"

for i in range(1, 11):
    with open(f"{log_dir}/log_{i:03d}.txt", "wb") as f:
        for j in range(5):
            if i == 4 and j == 2:
                # Corrupted encoding payload
                payload = b"{\"sensor_reading\": 2000.00000005, \"msg\": \"bad\xff\"}"
            else:
                # Normal payload
                payload = b"{\"sensor_reading\": 1000.00000005, \"msg\": \"ok\"}"

            b64_payload = base64.b64encode(payload).decode("utf-8")
            line = f"2023-10-01T12:00:00Z INFO {b64_payload}\n".encode("utf-8")
            f.write(line)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
