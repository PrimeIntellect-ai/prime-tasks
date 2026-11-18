#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    # Generate policy image
    mkdir -p /app
    convert -size 800x300 xc:white -font DejaVu-Sans -pointsize 32 -fill black \
        -draw "text 20,80 'AUTHORIZED CONFIGURATION POLICY'" \
        -draw "text 20,150 'DEPARTMENT_CODE: OMEGA-77-XRAY'" \
        -draw "text 20,220 'DO NOT SHARE'" \
        /app/policy.png

    # Generate corpora using Python
    python3 -c "
import tarfile
import os

os.makedirs('/app/corpora/clean', exist_ok=True)
os.makedirs('/app/corpora/evil', exist_ok=True)

# Generate clean tarballs
for i in range(1, 11):
    with tarfile.open(f'/app/corpora/clean/clean_{i:02d}.tar', 'w') as tar:
        with open('settings.conf', 'w') as f:
            f.write('DEPT=OMEGA-77-XRAY\n')
        tar.add('settings.conf')
        with open('data.txt', 'w') as f:
            f.write('safe data\n')
        tar.add('data.txt')

# Generate evil tarballs
def make_evil(name, paths, dept='OMEGA-77-XRAY', include_conf=True):
    with tarfile.open(f'/app/corpora/evil/{name}', 'w') as tar:
        if include_conf:
            with open('settings.conf', 'w') as f:
                f.write(f'DEPT={dept}\n')
            tar.add('settings.conf')
        for p in paths:
            with open('dummy', 'w') as f:
                f.write('evil')
            info = tarfile.TarInfo(p)
            info.size = 4
            with open('dummy', 'rb') as f:
                tar.addfile(info, f)

make_evil('evil_01_zipslip_abs.tar', ['/etc/cron.d/malicious'])
make_evil('evil_02_zipslip_rel.tar', ['../../../home/user/.bashrc'])
make_evil('evil_03_zipslip_mixed.tar', ['config/../../root/.ssh/authorized_keys'])
make_evil('evil_04_wrong_dept.tar', ['data.txt'], dept='ALPHA-11-BRAVO')
make_evil('evil_05_missing_conf.tar', ['data.txt'], include_conf=False)
make_evil('evil_06_trick_path.tar', ['some_dir/../file.txt'])
"

    # Cleanup temp files from Python script
    rm -f settings.conf data.txt dummy

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
