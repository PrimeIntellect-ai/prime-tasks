#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq xxd
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/process_metrics.sh
#!/bin/bash

INPUT_FILE="/home/user/encoded_logs.txt"
OUTPUT_FILE="/home/user/decoded_metrics.json"

echo "[" > "$OUTPUT_FILE"

first=1
while IFS= read -r line; do
    id=$(echo "$line" | cut -d'|' -f1)
    enc=$(echo "$line" | cut -d'|' -f2)
    data=$(echo "$line" | cut -d'|' -f3)

    if [ "$enc" == "base64" ]; then
        decoded=$(echo "$data" | base64 -d 2>/dev/null)
    elif [ "$enc" == "hex" ]; then
        decoded=$(echo "$data" | xxd -r -p)
    else
        decoded=""
        idx=0
        len=${#data}
        while [ $idx -lt $len ]; do
            count_hex=${data:$idx:2}
            val_hex=${data:$idx+2:2}

            count=$((16#$count_hex)) 2>/dev/null || count=0

            if [ "$count" -eq 0 ]; then
                continue
            fi

            for ((i=0; i<count; i++)); do
                decoded="${decoded}${val_hex}"
            done
            idx=$((idx + 4))
        done
        decoded=$(echo "$decoded" | xxd -r -p)
    fi

    if [ $first -eq 1 ]; then
        first=0
    else
        echo "," >> "$OUTPUT_FILE"
    fi
    echo "  {\"id\": \"$id\", \"metric\": \"$decoded\"}" >> "$OUTPUT_FILE"

done < "$INPUT_FILE"

echo "]" >> "$OUTPUT_FILE"
EOF
    chmod +x /home/user/process_metrics.sh

    cat << 'EOF' > /home/user/encoded_logs.txt
1|base64|Q1BVX0xPQUQ9ODAl
2|hex|4d454d4f52595f55534147453d344742
3|RLE|024100000342
4|base64|RVJST1I9Ik91dCBvZiBtZW1vcnki
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
