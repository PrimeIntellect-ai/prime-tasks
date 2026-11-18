#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq socat gawk curl
    pip3 install pytest

    mkdir -p /app/loc-server

    cat << 'EOF' > /app/loc-server/start.sh
#!/bin/bash
cd "$(dirname "$0")"
socat TCP4-LISTEN:8080,bind=127.0.0.1,reuseaddr,fork EXEC:./handle_req.sh
EOF

    cat << 'EOF' > /app/loc-server/handle_req.sh
#!/bin/bash
cd "$(dirname "$0")"

# Read HTTP request headers
while read -r line; do
    line=$(echo "$line" | tr -d '\r\n')
    if [ -z "$line" ]; then
        break
    fi
done

# Read body
body=$(cat)
result=$(echo "$body" | ./process_data.sh)

# Send HTTP response
echo -ne "HTTP/1.1 200 OK\r\n"
echo -ne "Content-Type: application/json\r\n"
echo -ne "Content-Length: ${#result}\r\n"
echo -ne "Connection: close\r\n\r\n"
echo -ne "$result"
EOF

    cat << 'EOF' > /app/loc-server/process_data.sh
#!/bin/bash
export LC_ALL=C

sed 's/\\u/\\\\u/g' | jq -c '.' | while read -r line; do
    text=$(echo "$line" | jq -r '.text')
    max_chars=$(echo "$line" | jq -r '.max_chars')
    len=$(echo -n "$text" | awk '{print length($0)}')
    echo "$len $max_chars"
done | awk '
BEGIN {
    valid_count = 0
    invalid_count = 0
    sum_valid_len = 0
}
{
    len = $1
    max_chars = $2
    if (len <= max_chars) {
        valid_count++
        sum_valid_len += len
    } else {
        invalid_count++
    }
}
END {
    avg_valid_len = 0
    if (valid_count > 0) {
        avg_valid_len = sum_valid_len / valid_count
    }
    rolling_avg_3 = 0.00

    printf "{\n"
    printf "  \"valid_count\": %d,\n", valid_count
    printf "  \"invalid_count\": %d,\n", invalid_count
    printf "  \"avg_valid_len\": %.2f,\n", avg_valid_len
    printf "  \"rolling_avg_3\": %.2f\n", rolling_avg_3
    printf "}\n"
}
'
EOF

    chmod +x /app/loc-server/*.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
