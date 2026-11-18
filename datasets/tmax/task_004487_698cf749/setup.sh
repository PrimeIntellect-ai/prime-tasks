#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest fastapi uvicorn flask requests

    # Create vendored package
    mkdir -p /app/vendored/patch-processor/patch_processor

    cat << 'EOF' > /app/vendored/patch-processor/setup.py
from setuptools import setup, find_packages
setup(name='patch_processor', version='1.0.0', packages=find_packages())
EOF

    cat << 'EOF' > /app/vendored/patch-processor/patch_processor/__init__.py
from .parser import parse
EOF

    cat << 'EOF' > /app/vendored/patch-processor/patch_processor/parser.py
from .models import Patch
import re

def parse(diff_text):
    paths = []
    for line in diff_text.splitlines():
        if line.startswith('+++ b/'):
            paths.append(line[6:])
    p = Patch(paths)
    return p.paths
EOF

    cat << 'EOF' > /app/vendored/patch-processor/patch_processor/models.py
from .parser import parse

class Patch:
    def __init__(self, paths):
        self.paths = paths
EOF

    # Create corpora
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    for i in $(seq 1 10); do
        cat << EOF > /app/corpora/clean/${i}.diff
--- a/src/main${i}.py
+++ b/src/main${i}.py
@@ -1 +1 @@
-clean
+cleaner
EOF
    done

    for i in $(seq 1 10); do
        cat << EOF > /app/corpora/evil/${i}.diff
--- a/ios/Secrets/cert${i}.pem
+++ b/ios/Secrets/cert${i}.pem
@@ -1 +1 @@
-secret
+hacked
EOF
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
