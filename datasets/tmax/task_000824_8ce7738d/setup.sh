#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/uploads/images
    mkdir -p /home/user/uploads/backup

    cat << 'EOF' > /home/user/uploads/normal.txt
Just a normal text file uploaded by a user.
EOF

    cat << 'EOF' > /home/user/uploads/id_rsa_leaked
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACD1A9XzM+n4m7u5G5JzF5/5X3wPzF7X2ZzZzZzZzZzZzQAAAJiZzZzZzZ
-----END OPENSSH PRIVATE KEY-----
EOF

    cat << 'EOF' > /home/user/uploads/backup/config.key
Some config data here.
-----BEGIN OPENSSH PRIVATE KEY-----
fakebase64dataherethatlookslikeakey12345
morefakebase64data
-----END OPENSSH PRIVATE KEY-----
End of config data.
EOF

    cat << 'EOF' > /home/user/uploads/images/logo.png
PNG_MAGIC_BYTES
EOF

    chmod -R 777 /home/user

    # Fix specific permissions required by the initial state tests
    chmod 0755 /home/user/uploads
    chmod 0755 /home/user/uploads/images
    chmod 0755 /home/user/uploads/backup
    chmod 0644 /home/user/uploads/normal.txt
    chmod 0644 /home/user/uploads/id_rsa_leaked
    chmod 0777 /home/user/uploads/backup/config.key
    chmod 0644 /home/user/uploads/images/logo.png
