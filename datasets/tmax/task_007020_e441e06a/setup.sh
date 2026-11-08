#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/legacy.cpp
#include <iostream>
#include <vector>
#include <fstream>

using namespace std;

int main(int argc, char** argv) {
    if(argc!=2) {
        cerr << "Usage: " << argv[0] << " <filename>" << endl;
        return 1;
    }
    ifstream in(argv[1]);
    vector<int> arr;
    int x;
    while(in >> x) arr.push_back(x);

    long long max_sum = -1000000000000000LL;
    if (arr.empty()) max_sum = 0;
    int n = arr.size();

    for(int i=0; i<n; ++i) {
        for(int j=i; j<n; ++j) {
            long long sum = 0;
            for(int k=i; k<=j; ++k) {
                sum += arr[k];
            }
            if(sum > max_sum) max_sum = sum;
        }
    }

    cout << "Max subarray sum: " << max_sum << "\n";
    return 0;
}
EOF

    g++ -O0 /tmp/legacy.cpp -o /home/user/legacy_bin
    rm /tmp/legacy.cpp
    chmod +x /home/user/legacy_bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
