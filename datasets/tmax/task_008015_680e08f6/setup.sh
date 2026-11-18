#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/verify_hash.s
.global verify_asm
.text
verify_asm:
    # Minimal x86_64 asm: checks if first byte of token (in rdi) is 'A' (0x41)
    movzbl (%rdi), %eax
    cmp $0x41, %eax
    je .valid
    mov $0, %eax
    ret
.valid:
    mov $1, %eax
    ret
EOF

    cat << 'EOF' > /home/user/app/crypto_check.c
extern int verify_asm(const char* token);

int validate_token(const char* token) {
    if (!token) return 0;
    return verify_asm(token);
}
EOF

    cat << 'EOF' > /home/user/app/build.sh
#!/bin/bash
gcc -c crypto_check.c -o crypto_check.o
as verify_hash.s -o verify_hash.o
gcc -shared -o libsec.so crypto_check.o verify_hash.o
EOF
    chmod +x /home/user/app/build.sh

    cat << 'EOF' > /home/user/app/test_lib.py
import ctypes
import sys
import os

if len(sys.argv) != 2:
    sys.exit(1)

lib_path = os.path.join(os.path.dirname(__file__), 'libsec.so')
try:
    lib = ctypes.CDLL(lib_path)
    lib.validate_token.argtypes = [ctypes.c_char_p]
    lib.validate_token.restype = ctypes.c_int

    token = sys.argv[1].encode('utf-8')
    result = lib.validate_token(token)
    if result == 1:
        sys.exit(0)
    else:
        sys.exit(1)
except Exception as e:
    sys.exit(1)
EOF
    chmod +x /home/user/app/test_lib.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
