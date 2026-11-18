#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk openssh-client
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/uploads
    mkdir -p /home/user/.ssh

    cat << 'EOF' > /home/user/upload_server.sh
#!/bin/bash
# Simple upload handler reading from stdin
read -r line1
# Expecting: Filename: <name>
filename=$(echo "$line1" | grep "Filename:" | awk '{print $2}')
if [ -n "$filename" ]; then
    cat > "/home/user/uploads/$filename"
    echo "File $filename uploaded successfully."
else
    echo "Error: No filename provided."
fi
EOF
    chmod +x /home/user/upload_server.sh

    cat << 'EOF' > /home/user/payload.sh
#!/bin/bash
# Obfuscate the evidence
cat /home/user/evidence_raw.txt | rev | base64 > /home/user/evidence.dat
rm /home/user/evidence_raw.txt
EOF
    chmod +x /home/user/payload.sh

    echo "flag{bash_f0r3ns1cs_p4th_tr4v3rsal}" | rev | base64 > /home/user/evidence.dat

    echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDKX9... attacker@evil.com" > /home/user/.ssh/authorized_keys

    cat << 'EOF' > /home/user/sshd_config_custom
Port 2222
PermitRootLogin yes
PasswordAuthentication yes
X11Forwarding no
EOF

    chmod -R 777 /home/user
