#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv jq
    pip3 install pytest build

    mkdir -p /home/user/my_package/src

    cat << 'EOF' > /home/user/my_package/src/hello.py
def say_hello():
    print("Hello from my_package!")
EOF

    cat << 'EOF' > /home/user/my_package/pyproject.toml
[build-system]
requires = ["setuptools>=61.0"]
build-backend = "setuptools.build_meta"

[project]
description = "A simple package"
authors = [
  {name="Dev", email="dev@example.com"}
]
EOF

    cat << 'EOF' > /home/user/job_metadata.json
{
  "jobs": {
    "job_1122": {
      "expected_checksum": "a1b2c3d4e5f6"
    },
    "job_9981": {
      "expected_checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    }
  }
}
EOF

    cat << 'EOF' > /home/user/ci_build.sh
#!/bin/bash
URL=$1

# Flawed extraction:
JOB_ID=$(echo $URL | cut -d'=' -f2)

# Missing jq query
EXPECTED="unknown"

cd /home/user/my_package
python3 -m build

ACTUAL_CHECKSUM="12345" # hardcoded, needs fix

# Bad JSON serialization
echo "{ job_id: $JOB_ID, expected: $EXPECTED, actual: $ACTUAL_CHECKSUM, match: false }" > /home/user/result.json
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
