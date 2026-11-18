#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip shc binutils gzip sed coreutils findutils sudo
pip3 install pytest

mkdir -p /app

cat << 'EOF' > /app/legacy_packer.sh
#!/bin/bash
DIR="$1"
if [ ! -d "$DIR" ]; then
    exit 1
fi
cd "$DIR" || exit 1
COUNT=$(find . -type f | wc -l)
echo "PACK_START: $COUNT"
find . -type f | sed 's|^\./||' | LC_ALL=C sort | while read -r file; do
    SIZE=$(stat -c%s "$file")
    echo "===${file}===${SIZE}==="
    cat "$file" | sed 's/CONFIDENTIAL/[REDACTED_DATA]/g' | tr 'A-Za-z' 'N-ZA-Mn-za-m' | gzip -n -c -9 | base64 -w 0
    echo ""
done
EOF

shc -f /app/legacy_packer.sh -o /app/legacy_packer
strip /app/legacy_packer
rm -f /app/legacy_packer.sh /app/legacy_packer.sh.x.c
chmod +x /app/legacy_packer

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
