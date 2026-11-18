#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libjansson-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_semver.py
def compare_versions(v1: str, v2: str) -> int:
    def parse(v):
        parts = v.split('-')
        base = parts[0].split('.')
        major = int(base[0])
        minor = int(base[1])
        patch = int(base[2])
        tag = parts[1] if len(parts) > 1 else 'final'

        tag_weights = {'alpha': 1, 'beta': 2, 'rc': 3, 'final': 4}
        return (major, minor, patch, tag_weights.get(tag, 0))

    p1 = parse(v1)
    p2 = parse(v2)

    if p1 < p2:
        return -1
    elif p1 > p2:
        return 1
    return 0
EOF

    cat << 'EOF' > /home/user/requests.jsonl
{"env_id": 100, "timestamp": 1600000000, "current_version": "1.0.0-alpha", "target_version": "1.0.0-beta"}
{"env_id": 100, "timestamp": 1600000010, "current_version": "1.0.0-beta", "target_version": "1.0.0-rc"}
{"env_id": 100, "timestamp": 1600000020, "current_version": "1.0.0-rc", "target_version": "1.0.0"}
{"env_id": 100, "timestamp": 1600000070, "current_version": "1.0.0", "target_version": "1.0.1"}
{"env_id": 200, "timestamp": 1600000100, "current_version": "2.1.0", "target_version": "2.0.0"}
{"env_id": 200, "timestamp": 1600000110, "current_version": "2.0.0", "target_version": "2.1.0"}
EOF

    chmod -R 777 /home/user
