#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create vendored package directory
    mkdir -p /app/bash-json-reshaper-1.1

    # Create config.env with the perturbation
    cat << 'EOF' > /app/bash-json-reshaper-1.1/config.env
ENABLE_UNICODE_DECODE=0
EOF

    # Create reshape.sh
    cat << 'EOF' > /app/bash-json-reshaper-1.1/reshape.sh
#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$DIR/config.env"
export ENABLE_UNICODE_DECODE

python3 -c '
import sys, json, os

enable_decode = os.environ.get("ENABLE_UNICODE_DECODE", "0") == "1"

for line in sys.stdin:
    if not line.strip(): continue
    if not enable_decode and "\\u" in line:
        line = line.replace("\\u", "\\\\u")
    try:
        d = json.loads(line)
        doc_id = d.get("id", "")
        text = d.get("text", "")
        metrics = d.get("metrics", {})
        for k in sorted(metrics.keys()):
            print(f"{doc_id}\t{k}\t{metrics[k]}\t{text}")
    except Exception as e:
        pass
'
EOF
    chmod +x /app/bash-json-reshaper-1.1/reshape.sh

    # Create oracle script
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/run_pipeline_oracle.sh
#!/bin/bash
/app/bash-json-reshaper-1.1/reshape.sh | while IFS=$'\t' read -r id metric_name metric_value text; do
    echo "[$id] Metric $metric_name has value $metric_value. Note: $text"
done
EOF
    chmod +x /opt/oracle/run_pipeline_oracle.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
