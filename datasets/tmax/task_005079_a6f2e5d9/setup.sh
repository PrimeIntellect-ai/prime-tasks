#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create vendored package directory
    mkdir -p /app/mongogen-audit-0.5.0/mongogen

    # Create setup.py for the vendored package
    cat << 'EOF' > /app/mongogen-audit-0.5.0/setup.py
from setuptools import setup, find_packages

setup(
    name='mongogen-audit',
    version='0.5.0',
    packages=find_packages(),
)
EOF

    # Create __init__.py
    touch /app/mongogen-audit-0.5.0/mongogen/__init__.py

    # Create the buggy compiler.py
    cat << 'EOF' > /app/mongogen-audit-0.5.0/mongogen/compiler.py
import json

class PipelineBuilder:
    def __init__(self, collection):
        self.collection = collection
        self.pipeline = []

    def add_match(self, condition):
        self.pipeline.append({"$match": condition})

    def add_lookup(self, target, local, foreign, as_field):
        self.pipeline.append({"$lookup": {"from": target, "localField": "_id", "foreignField": foreign, "as": as_field}})

    def add_project(self, fields):
        proj = {f: 1 for f in fields}
        self.pipeline.append({"$project": proj})

    def to_json(self):
        return json.dumps(self.pipeline)
EOF

    # Install the vendored package in editable mode so it's in the Python path
    pip3 install -e /app/mongogen-audit-0.5.0

    # Create oracle program
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/build_pipeline_oracle.py
import sys
import json

def main():
    if len(sys.argv) < 2:
        sys.exit(1)

    data = json.loads(sys.argv[1])
    pipeline = []

    pipeline.append({"$match": {"status": data.get("match_status")}})

    pipeline.append({
        "$lookup": {
            "from": data.get("join_collection"),
            "localField": data.get("join_local_field"),
            "foreignField": data.get("join_foreign_field"),
            "as": data.get("join_as")
        }
    })

    fields = data.get("fields", [])
    proj = {f: 1 for f in fields}
    pipeline.append({"$project": proj})

    print(json.dumps(pipeline))

if __name__ == "__main__":
    main()
EOF

    chmod -R 755 /opt/oracle
    chmod -R 777 /app/mongogen-audit-0.5.0

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
