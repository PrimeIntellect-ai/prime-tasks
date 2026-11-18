#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ protobuf-compiler libprotobuf-dev binutils
pip3 install pytest

mkdir -p /home/user/project
cd /home/user/project

cat << 'EOF' > math_service.proto
syntax = "proto3";
message ComputeResult {
  int32 limit = 1;
  int32 result = 2;
}
EOF

cat << 'EOF' > algo.h
#ifndef ALGO_H
#define ALGO_H
int compute_sum(int limit);
#endif
EOF

cat << 'EOF' > algo.cc
#include "algo.h"
int compute_sum(int limit) {
    int sum = 0;
    for(int i=1; i<=limit; ++i) sum += i;
    return sum;
}
EOF

cat << 'EOF' > main.cc
#include <iostream>
#include <string>
#include "math_service.pb.h"
#include "algo.h"

int main(int argc, char** argv) {
    if(argc != 2) return 1;
    std::string url = argv[1];
    size_t pos = url.find("limit=");
    if(pos == std::string::npos) return 1;
    int limit = std::stoi(url.substr(pos + 6));

    ComputeResult res;
    res.set_limit(limit);
    res.set_result(compute_sum(limit));
    std::cout << res.ShortDebugString() << std::endl;
    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
