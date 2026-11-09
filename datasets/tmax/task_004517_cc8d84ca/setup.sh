#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/main.py
from router import parse_url
from utils import log_request

def handle_request(url):
    params = parse_url(url)
    log_request(url)
    return params

if __name__ == "__main__":
    print(handle_request("/home?user=test"))
EOF

    cat << 'EOF' > /home/user/project/router.py
import urllib.parse

# This is the memory leak
_route_cache = {}

def parse_url(url):
    """Parses URL query parameters and returns a dictionary."""
    if url in _route_cache:
        return _route_cache[url]

    parsed = urllib.parse.urlparse(url)
    params = urllib.parse.parse_qs(parsed.query)
    # Flatten single-item lists for simplicity
    params = {k: v[0] if len(v) == 1 else v for k, v in params.items()}

    _route_cache[url] = params
    return params
EOF

    cat << 'EOF' > /home/user/project/utils.py
def log_request(url):
    pass
EOF

    chmod -R 777 /home/user
