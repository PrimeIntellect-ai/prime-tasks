#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr golang imagemagick fonts-dejavu-core zip tar gzip
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Generate policy label image
    convert -size 600x100 xc:white -pointsize 24 -fill black -draw "text 10,50 'APPROVED_PREFIX: OMEGA_BUILD_v7'" /app/policy_label.png

    # Create clean corpus
    mkdir -p /tmp/clean1/OMEGA_BUILD_v7
    echo "clean" > /tmp/clean1/OMEGA_BUILD_v7/file.txt
    cd /tmp/clean1 && zip -r /app/corpora/clean/valid_1.zip OMEGA_BUILD_v7
    cd /tmp/clean1 && tar -czf /app/corpora/clean/valid_2.tar.gz OMEGA_BUILD_v7

    # Create evil corpus
    # evil_slip.zip
    cat << 'EOF' > /tmp/make_evil_zip.py
import zipfile
with zipfile.ZipFile('/app/corpora/evil/evil_slip.zip', 'w') as z:
    z.writestr('OMEGA_BUILD_v7/../../../etc/passwd', 'root:x:0:0:root:/root:/bin/bash')
EOF
    python3 /tmp/make_evil_zip.py

    # evil_absolute.tar.gz
    cat << 'EOF' > /tmp/make_evil_tar.py
import tarfile
import io
with tarfile.open('/app/corpora/evil/evil_absolute.tar.gz', 'w:gz') as t:
    info = tarfile.TarInfo('/etc/shadow')
    info.size = 4
    t.addfile(info, io.BytesIO(b'root'))
EOF
    python3 /tmp/make_evil_tar.py

    # evil_wrong_prefix.zip
    mkdir -p /tmp/evil_wrong/ALPHA_BUILD_v7
    echo "wrong" > /tmp/evil_wrong/ALPHA_BUILD_v7/main.go
    cd /tmp/evil_wrong && zip -r /app/corpora/evil/evil_wrong_prefix.zip ALPHA_BUILD_v7

    # evil_root_file.tar.gz
    mkdir -p /tmp/evil_root/OMEGA_BUILD_v7
    echo "root" > /tmp/evil_root/malicious.sh
    cd /tmp/evil_root && tar -czf /app/corpora/evil/evil_root_file.tar.gz malicious.sh OMEGA_BUILD_v7

    # evil_corrupt.zip
    echo "This is not a zip file" > /app/corpora/evil/evil_corrupt.zip

    # Clean up temp files
    rm -rf /tmp/clean1 /tmp/evil_wrong /tmp/evil_root /tmp/make_evil_zip.py /tmp/make_evil_tar.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
