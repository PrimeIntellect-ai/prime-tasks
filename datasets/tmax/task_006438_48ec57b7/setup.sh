#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/model

    # Create the FASTA file
    cat << 'EOF' > /home/user/model/proteins.fasta
>seq1
MKTLLLTLVVVTIVCLDLGYA
>seq2
MRWQEMGYIFYPRKLR
>seq3
MTEYKLVVVGAGGVGKSALTIQLIQNHFVDEYDPTIEDSYRKQVVIDGETCLLDILDTAGQ
>seq4
MSKGEELFTGVVPILVELDGDVNGHKFSVSGEGEGDATYGKLTLKFICTTGKLPVPWPTLV
EOF

    # Create the signals.csv file
    cat << 'EOF' > /home/user/model/signals.csv
1.0, 2.0, 3.0, 4.0
2.0, 4.0, 6.0, 8.001
1.0, 0.0, 1.0, 0.0
0.0, 1.0, 0.0, 1.0
EOF

    # Create the C++ code
    cat << 'EOF' > /home/user/model/fit_model.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <iomanip>
#include <cmath>

using namespace std;

// Parses FASTA and returns sequence lengths
vector<double> get_y() {
    ifstream file("/home/user/model/proteins.fasta");
    vector<double> y;
    string line, seq = "";
    while (getline(file, line)) {
        if (line[0] == '>') {
            if (seq.length() > 0) { y.push_back(seq.length()); seq = ""; }
        } else {
            seq += line;
        }
    }
    if (seq.length() > 0) y.push_back(seq.length());
    return y;
}

// Reads 4x4 X matrix from CSV
vector<vector<double>> get_X() {
    ifstream file("/home/user/model/signals.csv");
    vector<vector<double>> X(4, vector<double>(4, 0.0));
    string line;
    int row = 0;
    while (getline(file, line) && row < 4) {
        size_t pos = 0;
        int col = 0;
        while ((pos = line.find(',')) != string::npos && col < 3) {
            X[row][col] = stod(line.substr(0, pos));
            line.erase(0, pos + 1);
            col++;
        }
        X[row][col] = stod(line);
        row++;
    }
    return X;
}

// Simple 4x4 matrix inversion using Gaussian elimination
bool invert_matrix(vector<vector<double>>& A, vector<vector<double>>& invA) {
    int n = 4;
    vector<vector<double>> a = A;
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            invA[i][j] = (i == j) ? 1.0 : 0.0;
        }
    }
    for (int i = 0; i < n; i++) {
        double pivot = a[i][i];
        if (abs(pivot) < 1e-5) {
            cerr << "Error: Singular matrix." << endl;
            return false;
        }
        for (int j = 0; j < n; j++) {
            a[i][j] /= pivot;
            invA[i][j] /= pivot;
        }
        for (int k = 0; k < n; k++) {
            if (k != i) {
                double factor = a[k][i];
                for (int j = 0; j < n; j++) {
                    a[k][j] -= factor * a[i][j];
                    invA[k][j] -= factor * invA[i][j];
                }
            }
        }
    }
    return true;
}

int main() {
    vector<double> y = get_y();
    vector<vector<double>> X = get_X();

    // Compute X^T * X
    vector<vector<double>> XtX(4, vector<double>(4, 0.0));
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            for (int k = 0; k < 4; k++) {
                XtX[i][j] += X[k][i] * X[k][j];
            }
        }
    }

    // TODO: Add ridge penalty lambda = 0.1 to diagonal of XtX here


    // Invert XtX
    vector<vector<double>> invXtX(4, vector<double>(4, 0.0));
    if (!invert_matrix(XtX, invXtX)) {
        return 1;
    }

    // Compute X^T * y
    vector<double> XtY(4, 0.0);
    for (int i = 0; i < 4; i++) {
        for (int k = 0; k < 4; k++) {
            XtY[i] += X[k][i] * y[k];
        }
    }

    // Compute w = inv(XtX) * (X^T * y)
    vector<double> w(4, 0.0);
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            w[i] += invXtX[i][j] * XtY[j];
        }
    }

    for (int i = 0; i < 4; i++) {
        cout << fixed << setprecision(4) << w[i] << (i == 3 ? "" : " ");
    }
    cout << endl;

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
