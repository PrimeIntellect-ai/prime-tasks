#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make
    pip3 install pytest

    mkdir -p /home/user/pipeline
    cd /home/user/pipeline

    cat << 'EOF' > webhooks.txt
http://ci.internal/deploy?service=auth_service&version=2.0.0
http://ci.internal/deploy?service=payment_gateway&version=1.12.5
http://ci.internal/deploy?service=email_sender&version=1.4.1
EOF

    cat << 'EOF' > registry.json
{
  "services": {
    "auth_service": "1.5.2",
    "payment_gateway": "1.9.0",
    "email_sender": "1.4.0",
    "user_api": "1.1.1",
    "checkout_api": "2.0.0",
    "notification_worker": "1.0.0"
  },
  "dependencies": {
    "user_api": ["auth_service"],
    "checkout_api": ["auth_service", "payment_gateway"],
    "notification_worker": ["email_sender"]
  }
}
EOF

    cat << 'EOF' > version_checker.py
import json
import sys
from urllib.parse import urlparse

class SemVer:
    def __init__(self, version_str):
        parts = version_str.split('.')
        self.major = parts[0]
        self.minor = parts[1]
        self.patch = parts[2]

    def requires_migration(self, old_version):
        # BUG: comparing strings instead of ints
        if self.major > old_version.major:
            return True
        if self.major == old_version.major:
            # BUG: string subtraction is invalid, or string comparison
            # minor diff > 2
            if int(self.minor) - int(old_version.minor) > 2:
                return True
        return False

class DependencyGraph:
    def __init__(self, registry_file):
        with open(registry_file, 'r') as f:
            data = json.load(f)
        self.versions = data['services']
        # mapping of dependency -> list of services that depend on it
        self.reverse_deps = {}
        for service, deps in data['dependencies'].items():
            for dep in deps:
                if dep not in self.reverse_deps:
                    self.reverse_deps[dep] = []
                self.reverse_deps[dep].append(service)

    def get_dependents(self, service):
        return self.reverse_deps.get(service, [])

def process_webhooks(webhook_file, registry_file, output_file):
    graph = DependencyGraph(registry_file)
    migrations = set()

    with open(webhook_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line: continue

            # BUG: bad URL parsing
            # Extracting query params poorly
            query = line.split('?')[-1]
            params = query.split('&')
            service = ""
            version = ""
            for p in params:
                if p.startswith('service='):
                    service = p.replace('service=', '')
                if p.startswith('version='):
                    version = p.replace('version', '') # BUG: missing '='

            if service in graph.versions:
                old_v = SemVer(graph.versions[service])
                new_v = SemVer(version)

                if new_v.requires_migration(old_v):
                    for dep in graph.get_dependents(service):
                        migrations.add(dep)

    with open(output_file, 'w') as f:
        for m in sorted(list(migrations)):
            f.write(m + '\n')

if __name__ == "__main__":
    process_webhooks(sys.argv[1], sys.argv[2], sys.argv[3])
EOF

    cat << 'EOF' > Makefile
.PHONY: test

test:
	python3 version_checker.py webhooks.txt registry.json migration_plan.txt
	@echo "Checking output..."
	@diff -q migration_plan.txt expected.txt && echo "Test Passed!" || (echo "Test Failed!" && exit 1)
EOF

    cat << 'EOF' > expected.txt
checkout_api
user_api
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
