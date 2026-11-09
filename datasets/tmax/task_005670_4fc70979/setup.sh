#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk tar gzip
pip3 install pytest

useradd -m -s /bin/bash user || true
mkdir -p /home/user
cd /home/user

# Create mock dataset
echo "id,value" > dataset.csv
for i in {1..1000}; do echo "$i,$RANDOM" >> dataset.csv; done
tar -czf raw_data.tar.gz dataset.csv
rm dataset.csv

# Create mock train_model.sh
cat << 'EOF' > /home/user/train_model.sh
#!/bin/bash
FILE=$1
REG=$2

if [ ! -f "$FILE" ]; then
    echo "Error: Dataset not found at $FILE" >&2
    exit 1
fi

T=${OPENBLAS_NUM_THREADS:-1}

# Calculate mock error: Minimum error is at T=2, R=0.1
awk -v t="$T" -v r="$REG" 'BEGIN { 
    err = (t - 2)^2 + (r - 0.1)^2 * 100 + 0.5; 
    printf "%.4f\n", err 
}'
EOF

chmod +x /home/user/train_model.sh

chmod -R 777 /home/user
