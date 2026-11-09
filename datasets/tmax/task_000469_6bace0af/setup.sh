#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/stat_oracle.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <cmath>
#include <iomanip>

using namespace std;

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    ifstream file(argv[1]);
    string line;
    getline(file, line); // skip header

    vector<double> control, treatment;

    while (getline(file, line)) {
        stringstream ss(line);
        string id, group, valA_str, valB_str;
        getline(ss, id, ',');
        getline(ss, group, ',');
        getline(ss, valA_str, ',');
        getline(ss, valB_str, ',');

        double val_A = stod(valA_str);
        double val_B = stod(valB_str);

        // Filtering rule
        if (val_A < 0.0 || val_B < 0.0) continue;

        // Derived feature
        double F = val_A + 0.5 * val_B;

        if (group == "control") control.push_back(F);
        else if (group == "treatment") treatment.push_back(F);
    }

    auto calc_mean = [](const vector<double>& v) {
        double sum = 0;
        for (double x : v) sum += x;
        return sum / v.size();
    };

    auto calc_var = [](const vector<double>& v, double mean) {
        double sum = 0;
        for (double x : v) sum += (x - mean) * (x - mean);
        return sum / (v.size() - 1);
    };

    double mean_c = calc_mean(control);
    double mean_t = calc_mean(treatment);
    double var_c = calc_var(control, mean_c);
    double var_t = calc_var(treatment, mean_t);

    double t_stat = (mean_t - mean_c) / sqrt(var_t / treatment.size() + var_c / control.size());

    cout << setprecision(6) << fixed << t_stat << endl;
    return 0;
}
EOF

    g++ -O3 -o /app/stat_oracle /app/stat_oracle.cpp
    strip /app/stat_oracle
    rm /app/stat_oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
