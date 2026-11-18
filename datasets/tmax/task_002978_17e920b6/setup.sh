#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    # Create directories
    mkdir -p /app/vendored/auth_parser-1.2.0/auth_parser
    mkdir -p /home/user/audit_logs
    mkdir -p /opt/oracle

    # Create auth_parser package
    cat << 'EOF' > /app/vendored/auth_parser-1.2.0/auth_parser/__init__.py
EOF

    cat << 'EOF' > /app/vendored/auth_parser-1.2.0/auth_parser/core.py
class Token:
    def __init__(self):
        self.is_valid = True

def validate_access_token(user_in_group, token):
    # Buggy line below: bitwise & instead of logical and, missing hashlib
    if user_in_group & token.is_valid:
        return True
    return False

def parse_acl_structure():
    return True
EOF

    cat << 'EOF' > /app/vendored/auth_parser-1.2.0/test_auth.py
import unittest
from auth_parser.core import validate_access_token, Token, parse_acl_structure

class TestAuth(unittest.TestCase):
    def test_validate(self):
        # This will raise TypeError if user_in_group is a list or something that doesn't support & with bool
        # Or just test with boolean
        self.assertTrue(validate_access_token(True, Token()))
    def test_parse(self):
        self.assertTrue(parse_acl_structure())

if __name__ == '__main__':
    unittest.main()
EOF

    # Create access.log with MD5 hash of 'apple'
    cat << 'EOF' > /home/user/audit_logs/access.log
2023-10-01 10:00:00 INFO User admin logged in. Hash: 1f3870be274f6c49b3e31a0c6728957f
2023-10-01 10:05:00 INFO User guest accessed public data.
EOF

    # Create oracle binary
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    FILE *f1 = fopen(argv[1], "rb");
    FILE *f2 = fopen(argv[2], "rb");
    if (!f1 || !f2) {
        if (f1) fclose(f1);
        if (f2) fclose(f2);
        return 1;
    }
    int c1, c2;
    while ((c1 = fgetc(f1)) != EOF && (c2 = fgetc(f2)) != EOF) {
        fputc(c1 ^ c2, stdout);
    }
    fclose(f1);
    fclose(f2);
    return 0;
}
EOF
    gcc /tmp/oracle.c -o /opt/oracle/perm_eval_oracle
    rm /tmp/oracle.c

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
