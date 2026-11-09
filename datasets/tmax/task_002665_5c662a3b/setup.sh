#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr fonts-dejavu-core gawk coreutils
    pip3 install pytest

    mkdir -p /app
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 'MASK_SALT: 9a3Bf1'" /app/salt.png

    cat << 'EOF' > /app/oracle.sh
#!/bin/bash
SALT="9a3Bf1"

awk -F, '
NR==1 {next}
{
    print $1, $2, $3
}' | sort -k1,1n | awk '
{
    ts=$1; dev=$2; val=$3;
    if (val == "") {
        if (!(dev in last_val)) val = 0.0;
        else val = last_val[dev];
    }
    last_val[dev] = val;

    win = int(ts / 3600) * 3600;
    print win, dev, val
}' | awk '
{
    win=$1; dev=$2; val=$3;
    if (!(win SUBSEP dev in max_val) || val > max_val[win, dev]) {
        max_val[win, dev] = val;
    }
}
END {
    for (comb in max_val) {
        split(comb, a, SUBSEP);
        win = a[1]; dev = a[2];
        print win, dev, max_val[comb]
    }
}' | while read win dev val; do
    hash=$(echo -n "${dev}${SALT}" | md5sum | cut -c1-8)
    echo "$win $hash $val"
done | sort -k1,1n -k2,2 | awk '{
    printf "{\"window\": %d, \"device\": \"%s\", \"max_val\": %.1f}\n", $1, $2, $3
}'
EOF
    chmod +x /app/oracle.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
