#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pipeline_project
    mkdir -p /home/user/diagnostics

    cat << 'EOF' > /home/user/pipeline_project/requirements.txt
pytest==7.4.0
EOF

    cat << 'EOF' > /home/user/pipeline_project/build.sh
#!/bin/bash
pip install -r req.txt
EOF
    chmod +x /home/user/pipeline_project/build.sh

    cat << 'EOF' > /home/user/pipeline_project/data.csv
id,value
101,50
102,75
103,25
104,CORRUPTED_DATA
105,100
106,10
107,INVALID
108,40
EOF

    cat << 'EOF' > /home/user/pipeline_project/pipeline.py
def process_data(lines):
    total_sum = 0
    header = True
    for line in lines:
        line = line.strip()
        if not line:
            continue
        if header:
            header = False
            continue

        parts = line.split(',')
        row_id = parts[0]
        row_value = parts[1]

        # TRACE LOGIC SHOULD GO HERE

        # RECOVERY LOGIC SHOULD WRAP THIS
        val = int(row_value)
        total_sum += val

    return total_sum

if __name__ == "__main__":
    with open('/home/user/pipeline_project/data.csv', 'r') as f:
        lines = f.readlines()

    total = process_data(lines)

    # OUTPUT RESULT LOGIC SHOULD GO HERE
EOF

    chmod -R 777 /home/user
