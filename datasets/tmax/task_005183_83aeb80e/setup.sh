#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip imagemagick gcc make tar gzip
pip3 install pytest

mkdir -p /app/corpus/clean/bundle_1
mkdir -p /app/corpus/evil/bundle_bad_archive
mkdir -p /app/corpus/evil/bundle_bad_encoding
mkdir -p /app/corpus/evil/bundle_bad_symlink
mkdir -p /app/corpus/evil/bundle_bad_mtime

# Create policy image
convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black -draw "text 10,50 'REPOSITORY POLICY: All manifests must include the string'" -draw "text 10,80 'APPROVED_ARTIFACT_v7_XYZ to be considered valid.'" /app/policy.png

# Create a valid tar.gz
echo "dummy data" > /tmp/dummy.txt
tar -czf /tmp/valid.tar.gz -C /tmp dummy.txt

# Create a corrupted tar.gz
head -c 50 /tmp/valid.tar.gz > /tmp/corrupt.tar.gz

# Helper texts
echo -n "some old text" > /tmp/nomagic.txt
echo -n "some text APPROVED_ARTIFACT_v7_XYZ more text" > /tmp/magic.txt

# bundle_1
iconv -f UTF-8 -t UTF-16LE /tmp/nomagic.txt > /app/corpus/clean/bundle_1/manifest_old.txt
iconv -f UTF-8 -t UTF-16LE /tmp/magic.txt > /app/corpus/clean/bundle_1/manifest_new.txt
cp /tmp/valid.tar.gz /app/corpus/clean/bundle_1/data.tar.gz
ln -s manifest_new.txt /app/corpus/clean/bundle_1/local_link
touch -d "2020-01-01" /app/corpus/clean/bundle_1/manifest_old.txt
touch -d "2023-01-01" /app/corpus/clean/bundle_1/manifest_new.txt

# bundle_bad_archive
iconv -f UTF-8 -t UTF-16LE /tmp/magic.txt > /app/corpus/evil/bundle_bad_archive/manifest_new.txt
cp /tmp/corrupt.tar.gz /app/corpus/evil/bundle_bad_archive/data.tar.gz

# bundle_bad_encoding
cat /tmp/magic.txt > /app/corpus/evil/bundle_bad_encoding/manifest.txt
cp /tmp/valid.tar.gz /app/corpus/evil/bundle_bad_encoding/data.tar.gz

# bundle_bad_symlink
iconv -f UTF-8 -t UTF-16LE /tmp/magic.txt > /app/corpus/evil/bundle_bad_symlink/manifest_new.txt
cp /tmp/valid.tar.gz /app/corpus/evil/bundle_bad_symlink/data.tar.gz
ln -s /etc/passwd /app/corpus/evil/bundle_bad_symlink/malicious_link

# bundle_bad_mtime
iconv -f UTF-8 -t UTF-16LE /tmp/magic.txt > /app/corpus/evil/bundle_bad_mtime/manifest_old.txt
iconv -f UTF-8 -t UTF-16LE /tmp/nomagic.txt > /app/corpus/evil/bundle_bad_mtime/manifest_new.txt
cp /tmp/valid.tar.gz /app/corpus/evil/bundle_bad_mtime/data.tar.gz
touch -d "2020-01-01" /app/corpus/evil/bundle_bad_mtime/manifest_old.txt
touch -d "2023-01-01" /app/corpus/evil/bundle_bad_mtime/manifest_new.txt

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
