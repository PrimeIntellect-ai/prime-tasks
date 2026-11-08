#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/candidates
    for i in $(seq 1 50); do
        echo "credential_candidate_random_value_$RANDOM" > /home/user/candidates/cred_$i.txt
    done
    echo -n "super_secret_rotation_key_88492" > /home/user/candidates/cred_37.txt

    cat << 'EOF' > /tmp/rotator.c
#include <stdio.h>

const char *approved_hash_1 = "3b1f6920f01ba3e6a9926d2e66bfeb0ccb3f56f1837b92f7b1e427cf63fc9098";
const char *approved_hash_2 = "0000000000000000000000000000000000000000000000000000000000000000";

int main() {
    printf("Credential Rotator v1.0\n");
    return 0;
}
EOF

    gcc /tmp/rotator.c -o /home/user/rotator
    rm /tmp/rotator.c

    cat << 'EOF' > /home/user/deploy.sh
#!/bin/bash
echo "Starting deployment of rotator service..."
cp /home/user/rotator /usr/local/bin/rotator
chown root:root /usr/local/bin/rotator
chmod 4777 /usr/local/bin/rotator
echo "Deployment complete."
EOF
    chmod +x /home/user/deploy.sh

    chmod -R 777 /home/user
