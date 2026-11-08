#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/app/fixtures

cat << 'EOF' > /home/user/app/fixtures/10_secure.json
{
    "path": "/secure",
    "handler": "auth_middleware"
}
EOF

cat << 'EOF' > /home/user/app/fixtures/99_catchall.json
{
    "path": "/*",
    "handler": "public_handler"
}
EOF

cat << 'EOF' > /home/user/app/mock_loader.py
import os
import json

def load_routing_mocks():
    routes = []
    # In CI, os.listdir order is unpredictable.
    files = os.listdir("/home/user/app/fixtures")

    # CI Simulation: Force reverse alphabetical order unless sorted
    if files == sorted(os.listdir("/home/user/app/fixtures")):
        files = sorted(files, reverse=True)

    for f in files:
        if f.endswith('.json'):
            with open(os.path.join("/home/user/app/fixtures", f)) as fp:
                routes.append(json.load(fp))
    return routes
EOF

cat << 'EOF' > /home/user/app/test_routing.py
from mock_loader import load_routing_mocks
import sys

def run_tests():
    routes = load_routing_mocks()
    if not routes:
        print("No routes loaded.")
        sys.exit(1)

    first_route = routes[0].get('path')
    if first_route == '/*':
        print("SECURITY FAILURE: Catch-all route loaded before secure routes!")
        sys.exit(1)
    elif first_route == '/secure':
        print("Tests passed.")
        with open('/home/user/build_success.log', 'w') as f:
            f.write("CI PASS\n")
        sys.exit(0)
    else:
        print("Unknown routing state.")
        sys.exit(1)

if __name__ == "__main__":
    run_tests()
EOF

cat << 'EOF' > /home/user/app/ci_pipeline.sh
#!/bin/bash
cd /home/user/app
python3 test_routing.py
EOF

chmod +x /home/user/app/ci_pipeline.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
