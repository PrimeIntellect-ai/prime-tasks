#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    touch "/home/user/data/file 1.txt"
    touch "/home/user/data/file2.txt"
    touch "/home/user/data/another file.txt"
    touch "/home/user/data/normal.txt"
    touch "/home/user/data/not_a_text_file.log"

    cat << 'EOF' > /home/user/backup.sh
#!/bin/bash
SOURCE=$1
DEST=$2
mkdir -p "$DEST"
for file in $(ls "$SOURCE"/*.txt 2>/dev/null); do
    cp $file "$DEST/"
done
EOF
    chmod +x /home/user/backup.sh

    chmod -R 777 /home/user
