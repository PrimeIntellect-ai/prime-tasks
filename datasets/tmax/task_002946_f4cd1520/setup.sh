#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth_checker.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

struct AuthData {
    char buffer[32];
    unsigned int is_admin;
};

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    struct AuthData auth;
    auth.is_admin = 0;

    fread(auth.buffer, 1, 128, f);
    fclose(f);

    if (auth.is_admin == 0xdeadbeef) {
        printf("AUTH_SUCCESS\n");
        FILE *out = fopen("/home/user/success.log", "w");
        fprintf(out, "EXPLOIT_SUCCESSFUL\n");
        fclose(out);
    } else {
        printf("AUTH_FAILED\n");
    }
    return 0;
}
EOF

    gcc -fno-stack-protector -O0 /home/user/auth_checker.c -o /home/user/auth_checker

    cat << 'EOF' > /home/user/scanner.py
import sys

def scan_file(filepath):
    try:
        with open(filepath, 'rb') as f:
            data = f.read()

        if not data:
            return True

        count = 1
        prev_byte = data[0]

        for byte in data[1:]:
            if byte == prev_byte:
                count += 1
                if count > 3:
                    print(f"SCANNER ALERT: Repeated padding detected (byte: {hex(byte)})")
                    return False
            else:
                count = 1
                prev_byte = byte

        return True
    except Exception as e:
        print(f"SCANNER ERROR: {e}")
        return False

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(1)
    if scan_file(sys.argv[1]):
        print("SCANNER: Payload clean.")
        sys.exit(0)
    else:
        sys.exit(1)
EOF

    cat << 'EOF' > /home/user/auth_wrapper.sh
#!/bin/bash
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <payload_file>"
    exit 1
fi

FILE=$1
if [ ! -f "$FILE" ]; then
    echo "File not found!"
    exit 1
fi

PREFIX=$(head -c 32 "$FILE")
tail -c +33 "$FILE" > /tmp/payload_body.bin

ACTUAL_MD5=$(md5sum /tmp/payload_body.bin | awk '{print $1}')

if [ "$PREFIX" != "$ACTUAL_MD5" ]; then
    echo "Integrity check failed. MD5 mismatch!"
    echo "Expected: $ACTUAL_MD5"
    echo "Got:      $PREFIX"
    exit 1
fi

echo "Integrity check passed."

python3 /home/user/scanner.py /tmp/payload_body.bin
if [ $? -ne 0 ]; then
    echo "Scanner blocked the payload."
    exit 1
fi

/home/user/auth_checker /tmp/payload_body.bin
EOF

    chmod +x /home/user/auth_wrapper.sh

    chmod -R 777 /home/user
