#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make curl jq
    pip3 install pytest pandas flask requests

    mkdir -p /app/vendor/bayes_classifier/bin
    mkdir -p /home/user

    cat << 'EOF' > /app/vendor/bayes_classifier/Makefile
PY_ENV=/usr/bin/pyton3

install:
	chmod +x bin/extract_features.sh bin/bayes_score
EOF

    cat << 'EOF' > /app/vendor/bayes_classifier/bin/extract_features.sh
#!/bin/bash
# Feature extraction script
/wrong/path/to/inference.py "$@"
EOF

    cat << 'EOF' > /app/vendor/bayes_classifier/bin/bayes_score
#!/usr/bin/env python3
import sys
import json

def main():
    if len(sys.argv) > 2 and sys.argv[1] == '--input':
        try:
            data = json.loads(sys.argv[2])
            score = 0.85
            if data.get('size_category') == 'large':
                score = 0.95
            print(json.dumps({"score": score}))
        except:
            print(json.dumps({"score": 0.5}))
    else:
        print(json.dumps({"score": 0.0}))

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/vendor/bayes_classifier/bin/bayes_score

    cat << 'EOF' > /home/user/raw_datasets.csv
dataset_id,creation_date,file_size_bytes
1,2022-12-01,500000
2,2023-01-15,50000000
3,2023-02-10,150000000
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
