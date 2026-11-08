#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /app/authproxy/tests
    touch /app/authproxy/__init__.py
    touch /app/authproxy/tests/__init__.py

    cat << 'EOF' > /app/authproxy/normalize.py
import unicodedata

def canonicalize_request(path: str, query: str) -> str:
    # Inefficient URL decoding
    decoded_path = path
    while '%' in decoded_path:
        for i in range(len(decoded_path)):
            if decoded_path[i] == '%':
                if i + 2 < len(decoded_path):
                    char = chr(int(decoded_path[i+1:i+3], 16))
                    decoded_path = decoded_path[:i] + char + decoded_path[i+3:]
                    break

    # Unicode normalization
    normalized_path = unicodedata.normalize('NFKC', decoded_path)

    # Inefficient query parameter sorting
    if not query:
        return normalized_path

    params = query.split('&')
    for i in range(len(params)):
        for j in range(len(params) - 1):
            if params[j] > params[j+1]:
                params[j], params[j+1] = params[j+1], params[j]

    return normalized_path + '?' + '&'.join(params)
EOF

    cat << 'EOF' > /app/authproxy/benchmark.py
import time
from normalize import canonicalize_request

def run_benchmark():
    path = "/api/v1/resource/" + "%20".join(["test"] * 1000)
    query = "&".join([f"k{i}=v{i}" for i in range(1000, 0, -1)])

    start = time.perf_counter()
    canonicalize_request(path, query)
    end = time.perf_counter()

    print(f"{end - start:.6f}")

if __name__ == "__main__":
    run_benchmark()
EOF

    cat << 'EOF' > /app/authproxy/tests/test_normalize.py
from authproxy.normalize import canonicalize_request

def test_canonicalize_request_basic():
    assert canonicalize_request("/api/%20test", "b=2&a=1") == "/api/ test?a=1&b=2"

def test_canonicalize_request_no_query():
    assert canonicalize_request("/api/%20test", "") == "/api/ test"

def test_canonicalize_request_unicode():
    # Test NFKC normalization
    assert canonicalize_request("/api/\u212B", "") == "/api/\u00C5"
EOF

    chmod -R 755 /app/authproxy

    # To allow python to find authproxy module
    export PYTHONPATH=/app:$PYTHONPATH
    echo "export PYTHONPATH=/app:\$PYTHONPATH" >> /etc/profile.d/pythonpath.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
