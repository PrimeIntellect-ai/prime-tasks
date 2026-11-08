#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip build-essential wget curl
pip3 install pytest

# Download and extract libcsv
mkdir -p /app
cd /app
wget https://sourceforge.net/projects/libcsv/files/libcsv/libcsv-3.0.3/libcsv-3.0.3.tar.gz
tar -xzf libcsv-3.0.3.tar.gz
rm libcsv-3.0.3.tar.gz

# Apply perturbations
cd libcsv-3.0.3
sed -i '45s/.*/CFLAGS = -O2 -wyntax_error_flag/' Makefile.in
sed -i '20s/.*/\/\/ missing include/' libcsv.c

mkdir -p /home/user

# Create slow_reference.py
cat << 'EOF' > /home/user/slow_reference.py
import csv
import json
import argparse

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input')
    parser.add_argument('--filter-label')
    parser.add_argument('--sort-prop')
    parser.add_argument('--limit', type=int)
    parser.add_argument('--offset', type=int)
    parser.add_argument('--output')
    args = parser.parse_args()

    results = []
    with open(args.input, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) < 3: continue
            if row[1] == args.filter_label:
                try:
                    props = json.loads(row[2])
                    val = props.get(args.sort_prop)
                    if val is not None:
                        results.append((float(val), row))
                except:
                    pass

    results.sort(key=lambda x: x[0], reverse=True)

    with open(args.output, 'w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f)
        for _, row in results[args.offset : args.offset + args.limit]:
            writer.writerow(row)

if __name__ == '__main__':
    main()
EOF

# Create a mock dataset
cat << 'EOF' > /home/user/graph_results.csv
101,Person,"{""age"": 35, ""score"": 8.5}"
102,Person,"{""age"": 42, ""score"": 9.1}"
103,Company,"{""founded"": 2005, ""score"": 7.2}"
104,Person,"{""age"": 28, ""score"": 6.5}"
105,Person,"{""age"": 50, ""score"": 9.9}"
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
