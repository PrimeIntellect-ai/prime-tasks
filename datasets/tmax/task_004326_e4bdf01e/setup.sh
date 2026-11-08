#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create guard.bin
    cat << 'EOF' > /tmp/guard.c
#include <stdio.h>

const char dummy_data1[] = "Some random strings to pad the binary";
const char secret_key[] = "KEY_START:Z3r0D4yM4lw4r3K3y";
const int dummy_data2 = 0xdeadbeef;

int main() {
    printf("I am a benign guard process.\n");
    return 0;
}
EOF
    gcc -O2 /tmp/guard.c -o /home/user/guard.bin
    rm /tmp/guard.c

    # Create the bash script to be encrypted
    cat << 'EOF' > /tmp/payload.sh
#!/bin/bash
if [ "$ISOLATION_MODE" = "active" ]; then
    if [ -z "$USER" ] && [ -z "$HOME" ]; then
        echo "FLAG{Ev4s10n_P4yl04d_D3l1v3r3d}"
    else
        echo "FAILED: Environment not fully cleared."
    fi
else
    echo "FAILED: ISOLATION_MODE not active."
fi
EOF

    # Encrypt payload.sh with the key 'Z3r0D4yM4lw4r3K3y'
    python3 -c '
key = b"Z3r0D4yM4lw4r3K3y"
with open("/tmp/payload.sh", "rb") as f:
    pt = f.read()

ct = bytearray()
for i in range(len(pt)):
    ct.append(pt[i] ^ key[i % len(key)])

with open("/home/user/encrypted.dat", "wb") as f:
    f.write(ct)
'
    rm /tmp/payload.sh

    chmod -R 777 /home/user
