#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr
    pip3 install pytest

    mkdir -p /app

    # Create the tape label image
    convert -size 400x100 xc:white -fill black -pointsize 24 -gravity center -draw "text 0,0 'VALID TAPE MAGIC: BKP7'" /app/tape_label.png

    # Create the oracle script
    cat << 'EOF' > /app/oracle.sh
#!/bin/bash
while IFS= read -r line || [ -n "$line" ]; do
    # Regex to match exactly MAGIC|SIZE|DATA where SIZE is digits
    if [[ "$line" =~ ^([^|]+)\|([0-9]+)\|(.*)$ ]]; then
        magic="${BASH_REMATCH[1]}"
        size="${BASH_REMATCH[2]}"
        data="${BASH_REMATCH[3]}"

        if [ "$magic" == "BKP7" ] && [ "${#data}" -eq "$size" ]; then
            echo "OK: $data"
        else
            echo "ERR: $line"
        fi
    else
        echo "ERR: $line"
    fi
done
EOF
    chmod +x /app/oracle.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
