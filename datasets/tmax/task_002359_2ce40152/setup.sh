#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    echo -n "TOP_SECRET_AUDIT_DATA_12345" > /home/user/data/audit.log

    cat << 'EOF' > /home/user/test_secure_reader.sh
#!/bin/bash

# Compile to ensure latest code
gcc -O2 -Wall -o /home/user/secure_reader /home/user/secure_reader.c

# Test 1: Invalid Token
if AUTH_TOKEN="WRONG" /home/user/secure_reader /home/user/data/audit.log 2>/dev/null; then
    echo "FAIL: Expected exit code 1 on wrong token, got 0"
    exit 1
fi
if [ $? -ne 1 ]; then
    echo "FAIL: Expected exit code 1 on wrong token"
    exit 1
fi

# Test 2: Invalid Path Prefix
if AUTH_TOKEN="AUDITOR_TOKEN_99" /home/user/secure_reader /etc/passwd 2>/dev/null; then
    echo "FAIL: Expected exit code 2 on bad prefix"
    exit 1
fi
if [ $? -ne 2 ]; then
    echo "FAIL: Expected exit code 2 on bad prefix"
    exit 1
fi

# Test 3: Directory Traversal
if AUTH_TOKEN="AUDITOR_TOKEN_99" /home/user/secure_reader /home/user/data/../data/audit.log 2>/dev/null; then
    echo "FAIL: Expected exit code 2 on directory traversal"
    exit 1
fi
if [ $? -ne 2 ]; then
    echo "FAIL: Expected exit code 2 on directory traversal"
    exit 1
fi

# Test 4: Missing File
if AUTH_TOKEN="AUDITOR_TOKEN_99" /home/user/secure_reader /home/user/data/doesnotexist.txt 2>/dev/null; then
    echo "FAIL: Expected exit code 3 on missing file"
    exit 1
fi
if [ $? -ne 3 ]; then
    echo "FAIL: Expected exit code 3 on missing file"
    exit 1
fi

# Test 5: Valid Execution & Encryption check
# Python script to generate the expected XOR output for the known plaintext
python3 -c '
import sys
data = b"TOP_SECRET_AUDIT_DATA_12345"
key = 0x5A
sys.stdout.buffer.write(bytes([b ^ key for b in data]))
' > /home/user/expected_output.bin

AUTH_TOKEN="AUDITOR_TOKEN_99" /home/user/secure_reader /home/user/data/audit.log > /home/user/actual_output.bin
if ! cmp -s /home/user/expected_output.bin /home/user/actual_output.bin; then
    echo "FAIL: Output data does not match expected XORed output"
    exit 1
fi

# Test 6: Seccomp Source check
if ! grep -q "PR_SET_SECCOMP" /home/user/secure_reader.c; then
    echo "FAIL: PR_SET_SECCOMP not found in source code"
    exit 1
fi

echo "PASS"
exit 0
EOF

    chmod +x /home/user/test_secure_reader.sh
    chmod -R 777 /home/user
