#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git build-essential
pip3 install pytest numpy

mkdir -p /app
mkdir -p /home/user/py_engine

cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <sstream>
#include <cmath>

using namespace std;

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    ifstream file(argv[1]);
    string line;
    vector<double> vec;
    vector<vector<double>> adj;
    if (getline(file, line)) {
        stringstream ss(line);
        string val;
        while (getline(ss, val, ',')) vec.push_back(stod(val));
    }
    while (getline(file, line)) {
        stringstream ss(line);
        string val;
        vector<double> row;
        while (getline(ss, val, ',')) row.push_back(stod(val));
        adj.push_back(row);
    }
    int n = vec.size();
    for (int iter = 0; iter < 1000; iter++) {
        vector<double> next_vec(n, 0.0);
        for (int i = 0; i < n; i++) {
            for (int j = 0; j < n; j++) {
                next_vec[i] += adj[i][j] * vec[j];
            }
        }
        double diff = 0;
        for (int i = 0; i < n; i++) diff = max(diff, abs(next_vec[i] - vec[i]));
        vec = next_vec;
        if (diff < 1e-12) break;
    }
    for (int i = 0; i < n; i++) cout << vec[i] << "\n";
    return 0;
}
EOF

g++ -O3 /app/oracle.cpp -o /app/oracle_engine
strip /app/oracle_engine
rm /app/oracle.cpp

cat << 'EOF' > /home/user/py_engine/solver.py
import sys
import numpy as np

def solve(csv_file):
    with open(csv_file, 'r') as f:
        lines = f.readlines()
    vec = np.array([float(x) for x in lines[0].strip().split(',')])
    adj = np.array([[float(x) for x in line.strip().split(',')] for line in lines[1:]])
    n = len(vec)
    for _ in range(1000):
        next_vec = np.zeros(n)
        for i in range(n):
            for j in range(n):
                next_vec[i] += adj[i][j] * vec[j]

        diff = np.max(np.abs(next_vec - vec))
        vec = next_vec
        if diff < 1e-12:
            break

    for v in vec:
        print(v)

if __name__ == '__main__':
    solve(sys.argv[1])
EOF

cd /home/user/py_engine
git init
git config user.name "Developer"
git config user.email "dev@example.com"
git add solver.py
git commit -m "Initial commit"
git tag v1.0

for i in $(seq 2 153); do
    echo "# comment $i" >> solver.py
    git commit -am "Noise commit $i"
done

sed -i 's/diff = np.max(np.abs(next_vec - vec))/diff = np.float32(np.max(np.abs(next_vec - vec)))/' solver.py
git commit -am "Update diff calculation"

for i in $(seq 155 200); do
    echo "# comment $i" >> solver.py
    git commit -am "Noise commit $i"
done

git tag v2.0

cat << 'EOF' > /home/user/gen_data.py
import numpy as np
n = 100
np.random.seed(42)
vec = np.random.rand(n)
adj = np.random.rand(n, n)
adj = adj / adj.sum(axis=0, keepdims=True)
adj = adj * 0.9
with open('/home/user/eval_data.csv', 'w') as f:
    f.write(','.join(map(str, vec)) + '\n')
    for row in adj:
        f.write(','.join(map(str, row)) + '\n')
EOF

python3 /home/user/gen_data.py
rm /home/user/gen_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
