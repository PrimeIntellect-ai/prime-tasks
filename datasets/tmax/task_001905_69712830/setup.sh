#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user/ml_pipeline
    cd /home/user/ml_pipeline

    cat << 'EOF' > generate_data.py
import random
random.seed(42)
with open("dataset.csv", "w") as f:
    for _ in range(1000):
        features = [random.gauss(0, 5) for _ in range(5)]
        # target = 2*f0 - 1.5*f1 + 0.5*f2 + noise
        target = 2.0*features[0] - 1.5*features[1] + 0.5*features[2] + random.gauss(0, 2)
        row = features + [target]
        f.write(",".join(f"{x:.4f}" for x in row) + "\n")
EOF
    python3 generate_data.py
    rm generate_data.py

    cat << 'EOF' > main.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <cmath>
#include <numeric>

using namespace std;

struct Data {
    vector<vector<double>> X;
    vector<double> y;
};

Data load_data(const string& filename) {
    Data data;
    ifstream file(filename);
    string line;
    while (getline(file, line)) {
        stringstream ss(line);
        string val;
        vector<double> row;
        while (getline(ss, val, ',')) {
            row.push_back(stod(val));
        }
        data.y.push_back(row.back());
        row.pop_back();
        data.X.push_back(row);
    }
    return data;
}

// Bug: Computes and scales globally
void scale_data_globally(Data& data) {
    int n = data.X.size();
    int d = data.X[0].size();
    for (int j = 0; j < d; j++) {
        double mean = 0;
        for (int i = 0; i < n; i++) mean += data.X[i][j];
        mean /= n;
        double sq_sum = 0;
        for (int i = 0; i < n; i++) sq_sum += pow(data.X[i][j] - mean, 2);
        double std_dev = sqrt(sq_sum / n);
        for (int i = 0; i < n; i++) {
            data.X[i][j] = (data.X[i][j] - mean) / (std_dev + 1e-8);
        }
    }
}

vector<double> train_ridge(const vector<vector<double>>& X, const vector<double>& y, double alpha) {
    // Dummy / simplistic training for the task setup (gradient descent)
    int d = X[0].size();
    vector<double> w(d, 0.0);
    double lr = 0.01;
    for(int iter=0; iter<100; ++iter) {
        vector<double> grad(d, 0.0);
        for(size_t i=0; i<X.size(); ++i) {
            double pred = 0;
            for(int j=0; j<d; ++j) pred += w[j]*X[i][j];
            double err = pred - y[i];
            for(int j=0; j<d; ++j) grad[j] += err * X[i][j];
        }
        for(int j=0; j<d; ++j) {
            w[j] = w[j] - lr * (grad[j]/X.size() + alpha*w[j]);
        }
    }
    return w;
}

vector<double> predict(const vector<vector<double>>& X, const vector<double>& w) {
    vector<double> preds;
    for(size_t i=0; i<X.size(); ++i) {
        double p = 0;
        for(size_t j=0; j<w.size(); ++j) p += w[j]*X[i][j];
        preds.push_back(p);
    }
    return preds;
}

int main() {
    Data data = load_data("dataset.csv");

    // THE LEAK IS HERE
    scale_data_globally(data);

    vector<double> alphas = {0.1, 1.0, 10.0};
    int k_folds = 5;
    int fold_size = data.X.size() / k_folds;

    for (double alpha : alphas) {
        double total_mse = 0;
        for (int k = 0; k < k_folds; k++) {
            vector<vector<double>> X_train, X_val;
            vector<double> y_train, y_val;

            for (size_t i = 0; i < data.X.size(); i++) {
                if (i >= k * fold_size && i < (k + 1) * fold_size) {
                    X_val.push_back(data.X[i]);
                    y_val.push_back(data.y[i]);
                } else {
                    X_train.push_back(data.X[i]);
                    y_train.push_back(data.y[i]);
                }
            }

            vector<double> w = train_ridge(X_train, y_train, alpha);
            vector<double> preds = predict(X_val, w);

            double mse = 0;
            for (size_t i = 0; i < preds.size(); i++) {
                mse += pow(preds[i] - y_val[i], 2);
            }
            total_mse += mse / preds.size();
        }
        // User currently prints this, but needs to output to CSV with inference time
        cout << "Alpha: " << alpha << " MSE: " << total_mse / k_folds << endl;
    }
    return 0;
}
EOF

    cat << 'EOF' > Makefile
all:
	g++ -O3 -std=c++11 main.cpp -o pipeline_run
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/ml_pipeline
    chmod -R 777 /home/user
