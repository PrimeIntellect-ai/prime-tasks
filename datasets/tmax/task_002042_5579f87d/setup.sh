#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest chardet

useradd -m -s /bin/bash user || true

mkdir -p /home/user/raw_data

# Create UTF-8 file
printf "  Café Moca  \n  apple PIE \n\n" > /home/user/raw_data/file1.txt

# Create ISO-8859-1 file
printf "café moca\nBanana\n" | iconv -f UTF-8 -t ISO-8859-1 > /home/user/raw_data/file2.txt

# Create UTF-16LE file
printf " Apple   pie \n banana \n" | iconv -f UTF-8 -t UTF-16LE > /home/user/raw_data/file3.txt

chmod -R 777 /home/user
