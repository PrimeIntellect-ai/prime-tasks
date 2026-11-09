#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bash coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.sh
#!/bin/bash
mkdir -p /home/user/logs/full
mkdir -p /home/user/logs/diff

# Generate full backup (2000 lines)
for i in {1..2000}; do
    if (( i % 100 == 0 )); then
        echo "Log entry $i: User attempted to access ../../../etc/passwd MALICIOUS_ENTRY" >> /home/user/logs/full/system.log
    elif (( i % 75 == 0 )); then
        echo "Log entry $i: Normal access to ../assets/image.png" >> /home/user/logs/full/system.log
    else
        echo "Log entry $i: System running normally." >> /home/user/logs/full/system.log
    fi
done

# Generate diff backup (1500 lines)
rm -f /tmp/diff_full.log
for i in {2001..3500}; do
    if (( i % 50 == 0 )); then
        echo "Log entry $i: Download ../../data/secret.txt" >> /tmp/diff_full.log
    elif (( i % 110 == 0 )); then
        echo "Log entry $i: Exploit payload ../ MALICIOUS_ENTRY" >> /tmp/diff_full.log
    else
        echo "Log entry $i: Background task completed." >> /tmp/diff_full.log
    fi
done

# Split diff backup into 3 chunks
split -l 500 /tmp/diff_full.log /home/user/logs/diff/diff_chunk_
rm /tmp/diff_full.log
EOF

    bash /tmp/setup.sh
    rm /tmp/setup.sh

    chown -R user:user /home/user/logs
    chmod -R 777 /home/user
