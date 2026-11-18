#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tzdata jq
    pip3 install pytest pytz

    # Create vendored package
    mkdir -p /app/vendored/fsmeta-utils/fsmeta

    cat << 'EOF' > /app/vendored/fsmeta-utils/setup.py
from setuptools import setup, find_packages
setup(
    name="fsmeta-utils",
    version="1.0.0",
    packages=find_packages(),
)
EOF

    touch /app/vendored/fsmeta-utils/fsmeta/__init__.py

    cat << 'EOF' > /app/vendored/fsmeta-utils/fsmeta/validators.py
def validate_quota(size_bytes) return size_bytes > 0
EOF

    # Create corpora directories
    mkdir -p /app/tests/corpora/clean
    mkdir -p /app/tests/corpora/evil

    # Generate clean corpus
    for i in $(seq 1 50); do
        cat << EOF > /app/tests/corpora/clean/req_${i}.json
{
  "service_id": "service-${i}",
  "mount_path": "/data/service_${i}",
  "quota_bytes": 10485760,
  "log_timezone": "UTC"
}
EOF
    done

    # Generate evil corpus
    for i in $(seq 1 10); do
        cat << EOF > /app/tests/corpora/evil/evil_path_${i}.json
{
  "service_id": "evil-path-${i}",
  "mount_path": "/data/../etc/shadow",
  "quota_bytes": 10485760,
  "log_timezone": "UTC"
}
EOF
    done

    for i in $(seq 11 20); do
        cat << EOF > /app/tests/corpora/evil/evil_quota_high_${i}.json
{
  "service_id": "evil-quota-high-${i}",
  "mount_path": "/data/service_${i}",
  "quota_bytes": 107374182401,
  "log_timezone": "UTC"
}
EOF
    done

    for i in $(seq 21 30); do
        cat << EOF > /app/tests/corpora/evil/evil_quota_neg_${i}.json
{
  "service_id": "evil-quota-neg-${i}",
  "mount_path": "/data/service_${i}",
  "quota_bytes": -1024,
  "log_timezone": "UTC"
}
EOF
    done

    for i in $(seq 31 50); do
        cat << EOF > /app/tests/corpora/evil/evil_tz_${i}.json
{
  "service_id": "evil-tz-${i}",
  "mount_path": "/data/service_${i}",
  "quota_bytes": 10485760,
  "log_timezone": "America/Atlantis"
}
EOF
    done

    # Setup user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
