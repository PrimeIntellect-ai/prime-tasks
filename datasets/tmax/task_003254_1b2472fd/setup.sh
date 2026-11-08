#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data /home/user/scripts

    cat << 'EOF' > /home/user/data/raw_data.csv
id,val1,val2,label
1,0.8,0.2,1
2,0.4,0.1,0
3,0.9,0.3,1
4,0.1,0.9,1
5,0.2,0.5,0
EOF

    cat << 'EOF' > /home/user/scripts/evaluate.py
import argparse
import os
import sys

def main():
    if os.environ.get("PIPELINE_MODE") != "STRICT":
        print("")
        sys.exit(0)

    parser = argparse.ArgumentParser()
    parser.add_argument("--param", type=float, required=True)
    parser.add_argument("--input", type=str, required=True)
    args = parser.parse_args()

    # Deterministic mock outputs for testing
    if args.param == 0.1:
        score, ci_l, ci_u = 0.40, 0.30, 0.50
    elif args.param == 0.5:
        score, ci_l, ci_u = 0.70, 0.55, 0.85
    elif args.param == 0.9:
        score, ci_l, ci_u = 0.95, 0.45, 1.45
    else:
        score, ci_l, ci_u = 0.0, 0.0, 0.0

    print(f"SCORE: {score:.2f} CI_LOWER: {ci_l:.2f} CI_UPPER: {ci_u:.2f}")

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /home/user/pipeline.sh
#!/bin/bash

# Broken ETL
cat /home/user/data/raw_data.csv > /home/user/data/filtered.csv

# Missing env var
# export PIPELINE_MODE=...

# python3 /home/user/scripts/evaluate.py ...
EOF

    chmod +x /home/user/pipeline.sh /home/user/scripts/evaluate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
