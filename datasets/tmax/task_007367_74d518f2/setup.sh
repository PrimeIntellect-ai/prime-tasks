#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make
pip3 install pytest requests

mkdir -p /home/user/project/ext
mkdir -p /home/user/project/tests

cat << 'EOF' > /home/user/project/py_waf.py
def check_sqli(payload: str) -> bool:
    # Basic SQLi signature
    target = "UNION SELECT"
    return target in payload.upper()
EOF

cat << 'EOF' > /home/user/project/ext/waf.c
#include <string.h>
#include <ctype.h>

// Returns 1 if XSS signature found, 0 otherwise
int check_xss(const char* payload, int len) {
    for (int i = 0; i <= len; i++) { // VULNERABILITY: i <= len allows payload[i+1] to read out of bounds
        if (payload[i] == '<' && payload[i+1] == 's') {
            return 1;
        }
    }
    return 0;
}
EOF

cat << 'EOF' > /home/user/project/ext/Makefile
all: waf.c
	gcc waf.c -o libwaf.so
EOF

cat << 'EOF' > /home/user/project/tests/test_waf.py
import unittest
import requests
import ctypes
import os

class TestWAF(unittest.TestCase):
    def test_upstream_proxy(self):
        # TODO: Mock requests.get to avoid network call
        response = requests.get("http://upstream.local/api")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.text, "OK")

    def test_xss_c(self):
        lib_path = os.path.join(os.path.dirname(__file__), '../ext/libwaf.so')
        if not os.path.exists(lib_path):
            self.fail("libwaf.so not built")
        lib = ctypes.CDLL(lib_path)
        payload = b"hello <script"
        self.assertEqual(lib.check_xss(payload, len(payload)), 1)

        safe_payload = b"hello world"
        self.assertEqual(lib.check_xss(safe_payload, len(safe_payload)), 0)
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/project
chmod -R 777 /home/user
