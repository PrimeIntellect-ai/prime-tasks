#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr xxd imagemagick fonts-dejavu-core
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /opt/oracle

    # Generate the archive tag image
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 36 -fill black -gravity center -draw "text 0,0 'ARCHIVE-77A-XYZ'" /app/archive_tag.png

    # Create the oracle script
    cat << 'EOF' > /opt/oracle/oracle.sh
#!/bin/bash
ID="ARCHIVE-77A-XYZ"

if [ ! -f "$1" ]; then
    echo "$ID|INVALID"
    exit 0
fi

len=$(wc -c < "$1")
if [ "$len" -lt 4 ]; then
    echo "$ID|INVALID"
    exit 0
fi

magic=$(head -c 4 "$1" | xxd -p)
if [ "$magic" != "7f454c46" ]; then
    echo "$ID|INVALID"
    exit 0
fi

bytes=$(head -c 16 "$1" | xxd -p | tr -d '\n')
padded=$(printf "%-32s" "$bytes" | tr ' ' '0')
echo "$ID|$padded"
EOF
    chmod +x /opt/oracle/oracle.sh

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
