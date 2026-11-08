#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip strace gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.config

    printf '2023-10-01T10:05:00Z svc status=200 bytes=1000\n2023-10-01T10:01:00Z svc status=200 bytes=200\n2023-10-01T10:03:00Z svc status=200 bytes=500\ncorrupted_line_with_binary_\x00\xff_garbage\n2023-10-01T10:02:00Z svc status=200 bytes=400\n2023-10-01T10:04:00Z svc status=200 bytes=100\n' > /home/user/raw_logs.txt

    cat << 'EOF' > /home/user/process.sh
#!/bin/bash
config="/home/user/.config/metrics.ini"
if [ ! -f "$config" ]; then
    echo "Error: missing config at $config" >&2
    exit 1
fi
source "$config"

if [ ! -f "/home/user/clean_logs.txt" ]; then
    echo "Error: missing clean_logs.txt" >&2
    exit 1
fi

awk -v mult="$FACTOR" '
{
    bytes = $4
    sub("bytes=", "", bytes)
    if (NR > 1) {
        diff = bytes - prev
        if (diff < 0) diff = -diff
        if (diff > max) max = diff
    }
    prev = bytes
}
END { print max * mult }
' /home/user/clean_logs.txt > /home/user/answer.txt
EOF
    chmod +x /home/user/process.sh

    chmod -R 777 /home/user
