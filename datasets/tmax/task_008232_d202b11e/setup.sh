#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/workspace/token_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

char* parse_token(char* input) {
    if (input == NULL) return NULL;
    int len = 0;
    char* data_start = NULL;

    if (strncmp(input, "TOKEN:", 6) == 0) {
        char* len_start = input + 6;
        char* colon = strchr(len_start, ':');
        if (colon != NULL) {
            *colon = '\0'; // Modifies input
            len = atoi(len_start);
            data_start = colon + 1;
            if (strlen(data_start) >= len) {
                data_start[len] = '\0'; // Modifies input
                return data_start;
            }
        }
    }
    return NULL;
}
EOF

    cat << 'EOF' > /home/user/workspace/security_tool.py
import ctypes

class SecurityTokenManager:
    def __init__(self, lib_path='/home/user/workspace/libtoken.so'):
        self.lib = ctypes.CDLL(lib_path)
        # Bug: missing argtypes and restype

    def create_token(self, payload):
        # Bug: returns str, needs to return bytes in Py3
        token_str = "TOKEN:" + str(len(payload)) + ":" + payload
        return token_str

    def extract_payload(self, raw_token):
        # Bug: passing immutable bytes directly, missing string buffer
        result = self.lib.parse_token(raw_token)
        if result:
            return ctypes.string_at(result).decode('utf-8')
        return None
EOF

    cat << 'EOF' > /home/user/workspace/test_security_tool.py
import unittest
from unittest.mock import patch, mock_open
from security_tool import SecurityTokenManager

class TestSecurityTokenManager(unittest.TestCase):
    def setUp(self):
        self.manager = SecurityTokenManager('/home/user/workspace/libtoken.so')

    def test_create_token(self):
        token = self.manager.create_token("secret_data")
        self.assertEqual(token, b"TOKEN:11:secret_data")

    def test_extract_payload(self):
        # Bug: mock_open read_data should be bytes
        with patch("builtins.open", mock_open(read_data="TOKEN:11:secret_data")):
            with open("fake_file", "rb") as f:
                data = f.read()
            payload = self.manager.extract_payload(data)
            self.assertEqual(payload, "secret_data")

if __name__ == '__main__':
    unittest.main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
