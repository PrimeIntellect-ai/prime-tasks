#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar gzip
    pip3 install pytest

    mkdir -p /home/user/incoming/
    mkdir -p /home/user/projects/
    mkdir -p /home/user/recent_code/

    cat << 'EOF' > /home/user/incoming/submissions.log
ID: sub_001
Status: APPROVED
File: proj1.tar.gz

ID: sub_002
Status: REJECTED
File: proj2.zip

ID: sub_003
Status: APPROVED
File: proj3.zip

ID: sub_004
Status: APPROVED
File: proj4.tar.gz

ID: sub_005
Status: APPROVED
File: proj5.zip
EOF

    # Create proj1.tar.gz (Safe, contains recent py file)
    mkdir -p /tmp/proj1
    echo "print('hello')" > /tmp/proj1/main.py
    echo "readme" > /tmp/proj1/README.md
    touch -d "2 days ago" /tmp/proj1/main.py
    touch -d "10 days ago" /tmp/proj1/README.md
    cd /tmp && tar -czf /home/user/incoming/proj1.tar.gz proj1

    # Create proj2.zip (Rejected, doesn't matter)
    mkdir -p /tmp/proj2
    echo "ignored" > /tmp/proj2/ignore.txt
    cd /tmp && zip -r /home/user/incoming/proj2.zip proj2

    # Create proj3.zip (Malicious Zip Slip)
    python3 -c "
import zipfile
with zipfile.ZipFile('/home/user/incoming/proj3.zip', 'w') as zf:
    zf.writestr('../../../evil.sh', 'echo malicious')
    zf.writestr('normal.txt', 'normal')
"

    # Create proj4.tar.gz (Malicious Tar Slip)
    python3 -c "
import tarfile
with tarfile.open('/home/user/incoming/proj4.tar.gz', 'w:gz') as tf:
    ti = tarfile.TarInfo(name='../../etc/passwd_fake')
    ti.size = 4
    import io
    tf.addfile(ti, io.BytesIO(b'evil'))
"

    # Create proj5.zip (Safe, contains old py file and recent py file)
    mkdir -p /tmp/proj5
    echo "print('old')" > /tmp/proj5/old.py
    echo "print('new')" > /tmp/proj5/new.py
    touch -d "20 days ago" /tmp/proj5/old.py
    touch -d "1 day ago" /tmp/proj5/new.py
    cd /tmp && zip -r /home/user/incoming/proj5.zip proj5

    # Clean up /tmp
    rm -rf /tmp/proj1 /tmp/proj2 /tmp/proj5

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
