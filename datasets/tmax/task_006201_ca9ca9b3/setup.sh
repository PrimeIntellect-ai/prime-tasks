#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/spool/manifests
    mkdir -p /home/user/spool/chunks
    mkdir -p /home/user/project_root
    mkdir -p /home/user/logs

    echo -n "Hello " > /home/user/spool/chunks/file1.part1
    echo -n "World!" > /home/user/spool/chunks/file1.part2

    echo -n "Secret " > /home/user/spool/chunks/file2.part1
    echo -n "Data" > /home/user/spool/chunks/file2.part2

    echo -n "Bad " > /home/user/spool/chunks/file3.part1
    echo -n "Checksum" > /home/user/spool/chunks/file3.part2

    cat << 'EOF' > /home/user/drop_manifests.sh
#!/bin/bash
# Valid manifest
cat << 'MAN' > /home/user/spool/manifests/doc.manifest
DEST:docs/hello.txt
CHUNKS:2
/home/user/spool/chunks/file1.part1
/home/user/spool/chunks/file1.part2
CHECKSUM:103
MAN

# Path traversal manifest (Zip Slip)
cat << 'MAN' > /home/user/spool/manifests/evil.manifest
DEST:../user/evil.txt
CHUNKS:2
/home/user/spool/chunks/file2.part1
/home/user/spool/chunks/file2.part2
CHECKSUM:241
MAN

# Bad checksum manifest
cat << 'MAN' > /home/user/spool/manifests/bad.manifest
DEST:docs/bad.txt
CHUNKS:2
/home/user/spool/chunks/file3.part1
/home/user/spool/chunks/file3.part2
CHECKSUM:99
MAN

EOF
    chmod +x /home/user/drop_manifests.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
