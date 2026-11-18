#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git
pip3 install pytest

mkdir -p /home/user/checksum_service
cd /home/user/checksum_service
git init
git config user.email "maintainer@example.com"
git config user.name "Maintainer"

cat << 'EOF' > README.md
# Checksum Service
A lightweight python service for checksum calculation.
EOF
git add README.md
git commit -m "Initial commit"

git checkout -b pr-12

cat << 'EOF' > checksums.py
import zlib

def crc32_checksum(payload: str) -> int:
    return zlib.crc32(payload.encode('utf-8'))

def custom_sum(payload: str) -> int:
    # BUG: Memory hog implementation
    expanded = payload * 10000
    total = 0
    for char in expanded:
        total = (total + ord(char)) % 256
    return total
EOF

cat << 'EOF' > router.py
import urllib.parse
from checksums import crc32_checksum, custom_sum

def route_request(path: str):
    # Expected format: /checksum/<algo>/<payload>
    parts = path.strip("/").split("/")

    if len(parts) == 3 and parts[0] == "checksum":
        algo = parts[1]
        payload = parts[2]

        # BUG: missing URL decoding here!

        if algo == "crc32":
            return crc32_checksum(payload)
        elif algo == "custom_sum":
            return custom_sum(payload)

    return {"error": "Not Found"}
EOF

cat << 'EOF' > test_service.py
import unittest
import tracemalloc
from router import route_request

class TestChecksumService(unittest.TestCase):

    def test_crc32_routing(self):
        result = route_request("/checksum/crc32/hello")
        self.assertEqual(result, 907060870)

    def test_url_decoding(self):
        # Payload is "hello world" encoded
        result = route_request("/checksum/custom_sum/hello%20world")
        # sum of ordinals of "hello world" is 1116. 
        # 1116 * 10000 = 11160000. 11160000 % 256 = 128
        self.assertEqual(result, 128)

    def test_memory_usage_custom_sum(self):
        large_payload = "abcdefghijklmnopqrstuvwxyz" * 1000 
        # Expected mathematically:
        # sum of "a..z" = 2847
        # 2847 * 1000 * 10000 = 28470000000. % 256 = 0

        tracemalloc.start()
        result = route_request(f"/checksum/custom_sum/{large_payload}")
        current, peak = tracemalloc.get_traced_memory()
        tracemalloc.stop()

        self.assertEqual(result, 0)
        # Peak memory should be less than 1MB (1048576 bytes)
        # The buggy version will use 26 * 1000 * 10000 chars = 260 MB
        self.assertLess(peak, 1024 * 1024, "Memory usage exceeded 1MB. Optimize custom_sum implementation!")

if __name__ == '__main__':
    unittest.main()
EOF

git add checksums.py router.py test_service.py
git commit -m "Add custom_sum and checksum routing"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
