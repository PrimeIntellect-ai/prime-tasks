#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-liberation gawk
    pip3 install pytest

    mkdir -p /app

    # Generate the rules image
    convert -size 400x100 xc:white -font Liberation-Sans -pointsize 36 -fill black -annotate +20+50 "BAN: TEST_EVENT" /app/rules.png

    # Create the oracle script
    cat << 'EOF' > /app/oracle_clean.sh
#!/bin/bash
awk -F',' '
BEGIN { OFS="," }
$3 != "TEST_EVENT" {
    # Normalize
    $3 = toupper($3)
    $4 = sprintf("%.2f", $4)

    # Deduplicate: Keep max timestamp, tie-break by latest in stream
    if (!($2 in max_ts) || $1 >= max_ts[$2]) {
        max_ts[$2] = $1
        record[$2] = $2 "," $1 "," $3 "," $4
    }
}
END {
    for (u in record) {
        print record[u]
    }
}' | sort -t',' -k1,1
EOF
    chmod +x /app/oracle_clean.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
