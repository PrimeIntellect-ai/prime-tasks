#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/data.csv
freq,psd
0.0,0.00
1.0,9.00
2.0,16.00
3.0,21.00
4.0,24.00
5.0,25.00
6.0,24.00
7.0,21.00
8.0,16.00
9.0,9.00
10.0,0.00
EOF

    cat << 'EOF' > /home/user/reference.txt
150.0
EOF

    cat << 'EOF' > /home/user/analyze_spectra.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <sstream>
#include <iomanip>

using namespace std;

double computeTotalEnergy(const vector<double>& freq, const vector<double>& psd) {
    double total_energy = 0.0;
    // TODO: Implement the trapezoidal rule for numerical integration here

    return total_energy;
}

int main(int argc, char* argv[]) {
    if (argc != 3) {
        cerr << "Usage: " << argv[0] << " <data.csv> <reference.txt>" << endl;
        return 1;
    }

    ifstream dataFile(argv[1]);
    vector<double> freq, psd;
    string line;

    // Skip header
    getline(dataFile, line);

    while (getline(dataFile, line)) {
        stringstream ss(line);
        string f_str, p_str;
        getline(ss, f_str, ',');
        getline(ss, p_str, ',');
        freq.push_back(stod(f_str));
        psd.push_back(stod(p_str));
    }

    ifstream refFile(argv[2]);
    double reference_energy;
    refFile >> reference_energy;

    double energy = computeTotalEnergy(freq, psd);

    ofstream outFile("/home/user/result.txt");
    outFile << fixed << setprecision(2);
    outFile << "Total Energy: " << energy << "\n";
    outFile << "Exceeds Reference: " << (energy > reference_energy ? "Yes" : "No") << "\n";
    outFile.close();

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
