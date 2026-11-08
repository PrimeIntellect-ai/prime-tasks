#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip systemd
    pip3 install pytest ruamel.yaml

    # Create oracle
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/manifest-processor-oracle
#!/usr/bin/env python3
import sys
from ruamel.yaml import YAML

def process(data):
    if not data:
        return data
    try:
        pod_spec = data['spec']['template']['spec']
    except KeyError:
        return data

    # Add volume
    volumes = pod_spec.get('volumes')
    if volumes is None:
        volumes = []
        pod_spec['volumes'] = volumes

    if not any(v.get('name') == 'audit-vault' for v in volumes):
        volumes.append({'name': 'audit-vault', 'emptyDir': {}})

    # Add volumeMounts
    containers = pod_spec.get('containers', [])
    for c in containers:
        mounts = c.get('volumeMounts')
        if mounts is None:
            mounts = []
            c['volumeMounts'] = mounts
        if not any(m.get('name') == 'audit-vault' for m in mounts):
            mounts.append({'name': 'audit-vault', 'mountPath': '/var/log/audit'})

    return data

def main():
    yaml = YAML()
    yaml.preserve_quotes = True
    try:
        docs = list(yaml.load_all(sys.stdin))
        processed = [process(d) for d in docs]
        yaml.dump_all(processed, sys.stdout)
    except Exception as e:
        pass

if __name__ == '__main__':
    main()
EOF
    chmod +x /opt/oracle/manifest-processor-oracle

    # Create vendored package
    mkdir -p /app/vendored/yaml-patcher-2.1.0
    cat << 'EOF' > /app/vendored/yaml-patcher-2.1.0/setup.py
from setuptools import setup

version = os.environ.get('PATCHER_VERSION', '2.1.0')

setup(
    name='yaml-patcher',
    version=version,
    scripts=['yaml-patcher'],
)
EOF

    cat << 'EOF' > /app/vendored/yaml-patcher-2.1.0/yaml-patcher
#!/usr/bin/env python3
import sys
if '--version' in sys.argv:
    print("2.1.0")
else:
    print("yaml-patcher running")
EOF
    chmod +x /app/vendored/yaml-patcher-2.1.0/yaml-patcher

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
