#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv perl ruby
pip3 install pytest

mkdir -p /home/user/diagnostics
cd /home/user/diagnostics

# 1. Raw Logs
cat << 'EOF' > raw_logs.txt
2023-10-01 10:00:00,NODE_A,cpu=50,mem=60,latency=5
2023-10-01 10:05:00,NODE_B,cpu=80,mem=90,latency=20
2023-10-01 10:10:00,NODE_C,cpu=20,mem=20,latency=
2023-10-01 10:15:00,NODE_D,cpu=10,mem=15,latency=2
EOF

# 2. requirements.txt (with artificial conflict)
cat << 'EOF' > requirements.txt
numpy==1.19.0
networkx==3.1
scipy>=1.10.0
EOF

# 3. extract.pl (Bug: fails on empty latency)
cat << 'EOF' > extract.pl
#!/usr/bin/env perl
use strict;
use warnings;

open my $in, '<', 'raw_logs.txt' or die "Cannot open raw_logs.txt: $!";
open my $out, '>', 'extracted_metrics.csv' or die "Cannot open extracted_metrics.csv: $!";

print $out "Node,CPU,Memory,Latency\n";

while (my $line = <$in>) {
    chomp $line;
    if ($line =~ /([^,]+),cpu=(\d+),mem=(\d+),latency=(\d+)/) {
        my $node = $1;
        my $cpu = $2;
        my $mem = $3;
        my $lat = $4;
        # Extract node name safely
        $node =~ s/.*,//; 
        print $out "$node,$cpu,$mem,$lat\n";
    }
}
close $in;
close $out;
EOF
chmod +x extract.pl

# 4. calculate_health.rb (Bug: wrong formula)
cat << 'EOF' > calculate_health.rb
#!/usr/bin/env ruby
require 'csv'

input = 'extracted_metrics.csv'
output = 'health_scores.csv'

CSV.open(output, 'w') do |csv_out|
  csv_out << ['Node', 'Score']
  CSV.foreach(input, headers: true) do |row|
    cpu = row['CPU'].to_f
    mem = row['Memory'].to_f
    latency = row['Latency'].to_f

    # BUG: Incorrect formula implementation
    score = 100 - cpu * 0.4 + 100 - mem * 0.4 + 1000 / latency + 1.0 * 0.2

    csv_out << [row['Node'], score.round(4)]
  end
end
EOF
chmod +x calculate_health.rb

# 5. topology_smoothing.py (Bug: missing normalization)
cat << 'EOF' > topology_smoothing.py
import csv
import json
import numpy as np

# Load scores
scores = {}
nodes = []
with open('health_scores.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        nodes.append(row['Node'])
        scores[row['Node']] = float(row['Score'])

n = len(nodes)
state = np.array([scores[node] for node in nodes], dtype=float)

# Adjacency matrix (fully connected with random weights, fixed seed)
np.random.seed(42)
A = np.random.rand(n, n)

# BUG: Missing row normalization here!
# A = A / A.sum(axis=1, keepdims=True)

# Iterate to find steady state
for _ in range(50):
    state = A.dot(state)

result = {nodes[i]: round(float(state[i]), 2) for i in range(n)}

with open('final_report.json', 'w') as f:
    json.dump(result, f, indent=4)
EOF

# 6. run_pipeline.sh
cat << 'EOF' > run_pipeline.sh
#!/bin/bash

echo "Setting up dependencies..."
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

echo "Running extraction..."
perl extract.pl

echo "Running health calculation..."
ruby calculate_health.rb

echo "Running topology smoothing..."
python topology_smoothing.py

echo "Done!"
EOF
chmod +x run_pipeline.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
