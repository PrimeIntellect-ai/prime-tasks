#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy

    mkdir -p /home/user/src /home/user/data

    cat << 'EOF' > /home/user/generate_data.py
import numpy as np
np.random.seed(42)
X = np.random.randn(100, 4) * 2.5 + 1.0
y = (X[:, 0] + X[:, 1] > 2.0).astype(int)
data = np.column_stack((X, y))
np.savetxt('/home/user/data/dataset.csv', data, delimiter=',', fmt='%.5f')
EOF
    python3 /home/user/generate_data.py

    cat << 'EOF' > /home/user/src/pipeline.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>
#include <cmath>
#include <numeric>
#include <algorithm>
#include <map>

using namespace std;

struct DataPoint {
    vector<double> features;
    int label;
    int original_index;
};

class StandardScaler {
    vector<double> means;
    vector<double> stds;
public:
    void fit(const vector<DataPoint>& data) {
        if(data.empty()) return;
        int n_features = data[0].features.size();
        means.assign(n_features, 0.0);
        stds.assign(n_features, 0.0);
        for(const auto& d : data) {
            for(int i=0; i<n_features; ++i) means[i] += d.features[i];
        }
        for(int i=0; i<n_features; ++i) means[i] /= data.size();

        for(const auto& d : data) {
            for(int i=0; i<n_features; ++i) {
                stds[i] += (d.features[i] - means[i]) * (d.features[i] - means[i]);
            }
        }
        for(int i=0; i<n_features; ++i) {
            stds[i] = sqrt(stds[i] / data.size());
            if(stds[i] == 0) stds[i] = 1.0;
        }
    }

    vector<DataPoint> transform(const vector<DataPoint>& data) {
        vector<DataPoint> res = data;
        int n_features = res[0].features.size();
        for(auto& d : res) {
            for(int i=0; i<n_features; ++i) {
                d.features[i] = (d.features[i] - means[i]) / stds[i];
            }
        }
        return res;
    }

    vector<double> transform_single(const vector<double>& x) {
        vector<double> res = x;
        for(size_t i=0; i<res.size(); ++i) {
            res[i] = (res[i] - means[i]) / stds[i];
        }
        return res;
    }
};

double euclidean_distance(const vector<double>& a, const vector<double>& b) {
    double sum = 0;
    for(size_t i=0; i<a.size(); ++i) sum += (a[i] - b[i])*(a[i] - b[i]);
    return sqrt(sum);
}

class KNN {
    int k;
    vector<DataPoint> train_data;
public:
    KNN(int k) : k(k) {}
    void fit(const vector<DataPoint>& data) { train_data = data; }

    int predict(const vector<double>& x, vector<int>& nearest_indices) {
        vector<pair<double, int>> dists;
        for(size_t i=0; i<train_data.size(); ++i) {
            dists.push_back({euclidean_distance(x, train_data[i].features), i});
        }
        sort(dists.begin(), dists.end());

        map<int, int> counts;
        int best_class = -1;
        int max_count = -1;
        nearest_indices.clear();
        for(int i=0; i<k && i<dists.size(); ++i) {
            int idx = dists[i].second;
            nearest_indices.push_back(train_data[idx].original_index);
            int label = train_data[idx].label;
            counts[label]++;
            if(counts[label] > max_count) {
                max_count = counts[label];
                best_class = label;
            }
        }
        return best_class;
    }
};

vector<DataPoint> load_data(const string& path) {
    vector<DataPoint> data;
    ifstream f(path);
    string line;
    int idx = 0;
    while(getline(f, line)) {
        stringstream ss(line);
        string val;
        DataPoint dp;
        dp.original_index = idx++;
        while(getline(ss, val, ',')) {
            dp.features.push_back(stod(val));
        }
        dp.label = dp.features.back();
        dp.features.pop_back();
        data.push_back(dp);
    }
    return data;
}

double evaluate_cv(vector<DataPoint> data, int k, int folds) {
    // BUG: Data leakage. Standardizing before splitting.
    StandardScaler scaler;
    scaler.fit(data);
    data = scaler.transform(data);

    int fold_size = data.size() / folds;
    double total_acc = 0;

    for(int i=0; i<folds; ++i) {
        vector<DataPoint> train, test;
        for(size_t j=0; j<data.size(); ++j) {
            if(j >= i*fold_size && j < (i+1)*fold_size) test.push_back(data[j]);
            else train.push_back(data[j]);
        }

        KNN knn(k);
        knn.fit(train);

        int correct = 0;
        for(const auto& t : test) {
            vector<int> dummy;
            if(knn.predict(t.features, dummy) == t.label) correct++;
        }
        total_acc += (double)correct / test.size();
    }
    return total_acc / folds;
}

int main() {
    auto data = load_data("/home/user/data/dataset.csv");
    // TODO: Fix the evaluate_cv function
    // TODO: Test K in [1, 3, 5, 7, 9]
    // TODO: Write to results.json
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
