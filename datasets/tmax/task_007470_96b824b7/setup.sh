#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/scripts /home/user/data

    cat << 'EOF' > /home/user/data/dataset.csv
feature_A,feature_B,feature_C,target
1.0,2.1,0.5,2.0
2.0,1.5,1.1,4.0
3.0,3.2,1.8,6.0
4.0,2.8,2.2,8.0
5.0,4.5,2.5,10.0
EOF

    cat << 'EOF' > /home/user/scripts/get_correlations.py
#!/usr/bin/env python3
import sys

# Hardcoded for the setup dataset to avoid requiring pandas in the environment if not needed, 
# or we can assume python3 is available. Let's just output the precomputed correlations for simplicity and robustness.
# feature_A: 1.0
# feature_B: 0.81
# feature_C: 0.98
print("feature_A:1.0")
print("feature_B:0.81")
print("feature_C:0.98")
EOF

    cat << 'EOF' > /home/user/scripts/run_inference.py
#!/usr/bin/env python3
import sys

if len(sys.argv) != 3:
    sys.exit(1)

dataset = sys.argv[1]
feature = sys.argv[2]

if feature == "feature_A":
    print("Inference results for feature_A: [2.0, 4.0, 6.0, 8.0, 10.0]")
else:
    print(f"Inference results for {feature}: [0.0, 0.0, 0.0, 0.0, 0.0]")
EOF

    chmod +x /home/user/scripts/*.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
