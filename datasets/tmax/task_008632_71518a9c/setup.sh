#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/compliance/scripts

    # Create a clean script
    cat << 'EOF' > /home/user/compliance/scripts/archive_logs.sh
#!/bin/bash
echo "Archiving older logs..."
tar -czf /var/log/archive.tar.gz /var/log/*.old
EOF

    # Create the original state of the tampered script to generate the good hash
    cat << 'EOF' > /home/user/compliance/scripts/process_logs.sh
#!/bin/bash
INPUT_DIR=$1
ls -l /var/log/app/"$INPUT_DIR"
EOF

    # Generate the sha256 checksums
    cd /home/user/compliance/scripts
    sha256sum archive_logs.sh process_logs.sh > /home/user/compliance/checksums.sha256

    # Overwrite process_logs.sh with the tampered/vulnerable version (CWE-78: OS Command Injection)
    cat << 'EOF' > /home/user/compliance/scripts/process_logs.sh
#!/bin/bash
INPUT_DIR=$1
# Tampered to allow command injection
eval "ls -l /var/log/app/$INPUT_DIR"
EOF

    chown -R user:user /home/user/compliance
    chmod -R 777 /home/user
