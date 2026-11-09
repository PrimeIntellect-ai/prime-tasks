#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr socat gawk imagemagick
    pip3 install pytest

    mkdir -p /app
    # Create the screenshot image
    convert -size 600x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,100 'API AUTH TOKEN: PERF_BASH_88X'" /app/auth_screenshot.png

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/handle_req.sh
#!/bin/bash
# Read HTTP headers
while read -r line; do
    line=$(echo "$line" | tr -d '\r')
    if [ -z "$line" ]; then break; fi
    # TODO: Add auth check here
done

# Read payload
read -r payload

# Buggy calculation (fails on 'ms' and spaces)
avg=$(echo "$payload" | awk -F',' '{sum+=$2; count++} END {print sum/count}')

echo -ne "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n"
echo "{\"average\": $avg}"
EOF

    chmod +x /home/user/handle_req.sh
    chmod -R 777 /home/user
