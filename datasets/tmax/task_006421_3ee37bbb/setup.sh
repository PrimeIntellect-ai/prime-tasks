#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/legacy_pipeline/data
mkdir -p /home/user/legacy_pipeline/logs

# Create input data
cat << 'EOF' > /home/user/legacy_pipeline/data/input.jsonl
{"id": 1, "name": "Alice", "target_value": 100}
{"id": 2, "name": "Bob"}
{"id": 3, "name": "Charlie", "target_value": 300
{"id": 4, "name": "Dave", "target_value": 400}
{"id": 5, "name": "Eve", "target_val: 500}
{"id": 6, "name": "Frank", "target_value": 600}
EOF

# Create extractor.py
cat << 'EOF' > /home/user/legacy_pipeline/extractor.py
import shutil
shutil.copy('/home/user/legacy_pipeline/data/input.jsonl', '/home/user/legacy_pipeline/data/extracted.jsonl')
print("Extraction complete")
EOF

# Create transformer.py
cat << 'EOF' > /home/user/legacy_pipeline/transformer.py
import json

with open('/home/user/legacy_pipeline/data/extracted.jsonl', 'r') as f_in, open('/home/user/legacy_pipeline/data/transformed.jsonl', 'w') as f_out:
    for line in f_in:
        line = line.strip()
        if not line: continue
        data = json.loads(line)
        data['transformed'] = True
        f_out.write(json.dumps(data) + '\n')
EOF

# Create loader.py
cat << 'EOF' > /home/user/legacy_pipeline/loader.py
import json

with open('/home/user/legacy_pipeline/data/transformed.jsonl', 'r') as f_in, open('/home/user/legacy_pipeline/data/output.jsonl', 'w') as f_out:
    for line in f_in:
        data = json.loads(line)
        # Bug: fails if target_value is missing
        val = data['target_value']
        data['final_value'] = val * 2
        f_out.write(json.dumps(data) + '\n')
EOF

# Create run_pipeline.sh
cat << 'EOF' > /home/user/legacy_pipeline/run_pipeline.sh
#!/bin/bash

python3 /home/user/legacy_pipeline/extractor.py
python3 /home/user/legacy_pipeline/transformer.py
python3 /home/user/legacy_pipeline/loader.py
echo "Pipeline finished successfully!"
EOF
chmod +x /home/user/legacy_pipeline/run_pipeline.sh

# Create logs
cat << 'EOF' > /home/user/legacy_pipeline/logs/extractor.log
1673856000 Extracting batch 1
1673856005 Extracting batch 2
EOF

cat << 'EOF' > /home/user/legacy_pipeline/logs/transformer.log
2023-01-16T08:00:02Z Transformed batch 1
2023-01-16T08:00:07Z Transformed batch 2
EOF

cat << 'EOF' > /home/user/legacy_pipeline/logs/loader.log
2023/01/16 08:00:04 Loaded batch 1
2023/01/16 08:00:09 Loaded batch 2
EOF

cat << 'EOF' > /home/user/legacy_pipeline/logs/loader_crash.log
Traceback (most recent call last):
  File "/home/user/legacy_pipeline/loader.py", line 7, in <module>
    val = data['target_value']
KeyError: 'target_value'
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
