#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv bc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/pipeline/input.csv
ID,Value
1,10.0
2,15.2
3,8.4
4,20.0
EOF

    cat << 'EOF' > /home/user/pipeline/expected.csv
ID,Value
1,25.0
2,38.0
3,21.0
4,50.0
EOF

    cat << 'EOF' > /home/user/pipeline/requirements.txt
pandas==1.3.5
numpy==2.0.0
EOF

    cat << 'EOF' > /home/user/pipeline/transform.py
import pandas as pd

df = pd.read_csv('input.csv')
# Bug: Casts to int before multiplication, losing precision, and adds a space after comma in output
df['Value'] = (df['Value'].astype(int) * 2.5)
df.to_csv('output.csv', index=False, sep=',', float_format='%.1f')
EOF

    cat << 'EOF' > /home/user/pipeline/build.sh
#!/bin/bash

# Setup environment
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Run transformation
python transform.py

# Diff analysis step (will fail if output.csv doesn't match expected.csv)
diff output.csv expected.csv

# Calculate metrics
# Data rows count (excluding header)
count=$(tail -n +2 output.csv | wc -l)
sum=$(awk -F, 'NR>1 {sum+=$2} END {print sum}' output.csv)

# Bug: No scale specified, precedence is wrong (divides then subtracts instead of groups)
# Intended: (sum / count) * 3.14159
score=$(echo "$sum / $count * 3.14159" | bc)

echo "$score" > final_score.txt
EOF

    chmod +x /home/user/pipeline/build.sh
    chmod -R 777 /home/user
