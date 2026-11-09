#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc protobuf-compiler golang-go
pip3 install pytest

# Create /app and compile clean_oracle
mkdir -p /app
cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
int main() {
    float a, b, c;
    while (scanf("%f,%f,%f", &a, &b, &c) == 3) {
        float ca = a * 2.0;
        float cb = b + 10.0;
        float cc = c < 0.0 ? 0.0 : c;
        printf("%f,%f,%f\n", ca, cb, cc);
    }
    return 0;
}
EOF
gcc -O3 -s /tmp/oracle.c -o /app/clean_oracle

# Create dataset
mkdir -p /home/user/data
cat << 'EOF' > /tmp/gen_data.py
import csv, random
random.seed(42)
with open('/home/user/data/train.csv', 'w') as f:
    writer = csv.writer(f)
    for _ in range(150):
        f1 = random.uniform(-5, 5)
        f2 = random.uniform(-5, 5)
        f3 = random.uniform(-5, 5)
        # Apply the oracle logic to generate target cleanly
        ca = f1 * 2.0
        cb = f2 + 10.0
        cc = f3 if f3 > 0 else 0.0
        # True weights: 1.5, -0.8, 3.2. True bias: 5.0
        target = 5.0 + 1.5 * ca - 0.8 * cb + 3.2 * cc + random.gauss(0, 0.1)
        writer.writerow([f1, f2, f3, target])
EOF
python3 /tmp/gen_data.py

# Create predictor.proto
cat << 'EOF' > /home/user/predictor.proto
syntax = "proto3";
option go_package = "./;main";
service Predictor {
  rpc Predict (PredictRequest) returns (PredictResponse) {}
}
message PredictRequest {
  double f1 = 1;
  double f2 = 2;
  double f3 = 3;
}
message PredictResponse {
  double prediction = 1;
}
EOF

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
