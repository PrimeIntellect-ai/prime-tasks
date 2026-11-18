#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr
pip3 install pytest

mkdir -p /app
mkdir -p /tmp/docs

for i in $(seq 1 10); do
  echo "Welcome to ACME_CORP. This is the USER_MANUAL for LEGACY_SYSTEM_V1." > /tmp/docs/doc_$i.txt
  echo "<doc><company>ACME_CORP</company><sys>LEGACY_SYSTEM_V1</sys></doc>" > /tmp/docs/data_$i.xml
done

tar -czf /tmp/clean.tar.gz -C /tmp docs
dd if=/dev/urandom of=/app/corrupted_docs.bin bs=1 count=512
cat /tmp/clean.tar.gz >> /app/corrupted_docs.bin

convert -background white -fill black -pointsize 24 label:"ARCHIVE_OFFSET=512\nACME_CORP=GLOBAL_TECH_INC\nLEGACY_SYSTEM_V1=CLOUD_NATIVE_V2\nUSER_MANUAL=ADMIN_GUIDE" /app/docs_config.png

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
