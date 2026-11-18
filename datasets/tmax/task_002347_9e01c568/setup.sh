#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        imagemagick \
        fonts-dejavu-core \
        expect \
        git \
        nginx \
        gcc \
        libc6-dev

    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil /home/user/bin

    cat << 'EOF' > /app/corpus/clean/valid1.log
2023-10-01T12:00:00Z,web-server-01,45.2,64.0,200
EOF

    cat << 'EOF' > /app/corpus/clean/valid2.log
2023-10-01T12:05:00Z,db-server-main,12.0,120.5,450
EOF

    cat << 'EOF' > /app/corpus/evil/malicious1.log
2023-10-01T12:00:00Z,web-server;rm -rf /,45.2,64.0,200
EOF

    cat << 'EOF' > /app/corpus/evil/malicious2.log
2023-10-01T12:00:00Z,web-server-01,-10,64.0,200
EOF

    cat << 'EOF' > /app/corpus/evil/malicious3.log
2023-10-01T12:00:00Z,web-server-01,45.2,notanumber,200
EOF

    # Generate the image with the thresholds
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 20 -fill black \
        -annotate +10+30 "SYSTEM CAPACITY THRESHOLDS\nMAX_CPU: 85\nMAX_MEM: 128\nMAX_DISK: 500" \
        /app/capacity_limits.png

    cat << 'EOF' > /home/user/bin/register_limits
#!/bin/bash
echo "Starting capacity registration..."
read -p "Enter MAX_CPU: " cpu
read -p "Enter MAX_MEM: " mem
read -p "Enter MAX_DISK: " disk
if [[ "$cpu" == "85" && "$mem" == "128" && "$disk" == "500" ]]; then
    echo "SUCCESS" > /home/user/.limits_registered
else
    echo "FAILED"
fi
EOF
    chmod +x /home/user/bin/register_limits

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
