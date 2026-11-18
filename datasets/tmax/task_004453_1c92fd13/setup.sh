#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ binutils
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <vector>
#include <cmath>
#include <iomanip>
#include <numeric>

using namespace std;

int main(int argc, char* argv[]) {
    if (argc < 3) return 1;
    int M = stoi(argv[1]);
    int N = stoi(argv[2]);
    if (argc != 3 + M * N) return 1;

    vector<vector<double>> chains(M, vector<double>(N));
    int idx = 3;
    for (int i = 0; i < M; ++i) {
        for (int j = 0; j < N; ++j) {
            chains[i][j] = stod(argv[idx++]);
        }
    }

    vector<double> chain_means(M);
    double overall_mean = 0;
    for (int i = 0; i < M; ++i) {
        double sum = 0;
        for (int j = 0; j < N; ++j) {
            sum += chains[i][j];
        }
        chain_means[i] = sum / N;
        overall_mean += chain_means[i];
    }
    overall_mean /= M;

    double B = 0;
    for (int i = 0; i < M; ++i) {
        B += (chain_means[i] - overall_mean) * (chain_means[i] - overall_mean);
    }
    B = (B * N) / (M - 1);

    double W = 0;
    for (int i = 0; i < M; ++i) {
        double var_sum = 0;
        for (int j = 0; j < N; ++j) {
            var_sum += (chains[i][j] - chain_means[i]) * (chains[i][j] - chain_means[i]);
        }
        W += var_sum / (N - 1);
    }
    W /= M;

    double V_hat = ((N - 1.0) / N) * W + (1.0 / N) * B;

    double R_hat = 1.0;
    if (W > 1e-12) {
        R_hat = sqrt(V_hat / W);
    }

    cout << fixed << setprecision(6) << R_hat << endl;
    return 0;
}
EOF
g++ -O3 /tmp/oracle.cpp -o /app/gelman_rubin_oracle
strip /app/gelman_rubin_oracle
rm /tmp/oracle.cpp

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
