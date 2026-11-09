#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git libyaml-dev gcc wget tar

pip3 install pytest pyyaml Cython

# Download and vendor PyYAML 6.0.1
mkdir -p /app/vendored
wget https://github.com/yaml/pyyaml/archive/refs/tags/6.0.1.tar.gz
tar -xzf 6.0.1.tar.gz -C /app/vendored
rm 6.0.1.tar.gz

# Modify setup.py to hardcode with_libyaml = False
python3 -c '
import sys
path = "/app/vendored/pyyaml-6.0.1/setup.py"
with open(path, "r") as f:
    content = f.read()
content = content.replace("with_libyaml = None", "with_libyaml = False")
content = content.replace("with_libyaml = True", "with_libyaml = False")
if "with_libyaml = False" not in content:
    content = content.replace("class build_ext(_build_ext):", "class build_ext(_build_ext):\n    with_libyaml = False")
with open(path, "w") as f:
    f.write(content)
'

# Create pipeline directory and run_benchmark.py
mkdir -p /home/user/pipeline
cat << 'EOF' > /home/user/pipeline/run_benchmark.py
import sys
import time
import json
import yaml

try:
    from yaml import CSafeLoader as Loader
except ImportError:
    from yaml import SafeLoader as Loader

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    dataset = sys.argv[1]

    start = time.time()
    with open(dataset, 'r') as f:
        data = yaml.load(f, Loader=Loader)
    end = time.time()

    elapsed = end - start
    with open("benchmark_results.json", "w") as f:
        json.dump({"time_taken": elapsed}, f)

if __name__ == "__main__":
    main()
EOF

# Generate large YAML file
python3 -c '
import yaml
data = [{"id": i, "value": f"item_{i}", "nested": {"a": 1, "b": [1,2,3]}} for i in range(100000)]
with open("/home/user/pipeline/massive_data.yaml", "w") as f:
    yaml.dump(data, f)
'

# Initialize git, stage the file, and delete it
cd /home/user/pipeline
git init
git config user.email "dev@example.com"
git config user.name "Dev"
git add massive_data.yaml
rm massive_data.yaml

# Setup user and permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
