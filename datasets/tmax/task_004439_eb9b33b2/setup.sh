#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y g++ imagemagick iproute2 openssh-server tesseract-ocr fonts-dejavu-core

    mkdir -p /app

    # Compile the oracle decryptor
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
using namespace std;
int main() {
    char c;
    while (cin.get(c)) {
        unsigned char uc = (unsigned char)c;
        uc = uc ^ 0x8C;
        uc = uc - 0x3A;
        cout.put((char)uc);
    }
    return 0;
}
EOF
    g++ -o /app/oracle_decryptor /app/oracle.cpp
    chmod +x /app/oracle_decryptor

    # Generate the ransom note image
    convert -size 800x100 xc:white -fill black -pointsize 24 -annotate +20+50 'ENCRYPTION ALGO: ADD 0x3A THEN XOR 0x8C' /app/ransom_note.png

    # Create the SUID backdoor
    cp /bin/true /var/tmp/.backdoor
    chmod 4755 /var/tmp/.backdoor

    # Modify SSH config to be vulnerable
    if grep -q "PermitRootLogin" /etc/ssh/sshd_config; then
        sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    else
        echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
    fi

    # Set up the rogue service to start when the container environment is loaded
    cat << 'EOF' > /.singularity.d/env/99-rogue.sh
#!/bin/sh
python3 -c "import socket, time; s=socket.socket(); s.bind(('', 8543)); s.listen(1); time.sleep(100000)" >/dev/null 2>&1 &
EOF
    chmod +x /.singularity.d/env/99-rogue.sh

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
