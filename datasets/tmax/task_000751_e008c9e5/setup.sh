#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make nlohmann-json3-dev
    pip3 install pytest

    # Create vendor package
    mkdir -p /app/vendor/libcsvquery
    cat << 'EOF' > /app/vendor/libcsvquery/csvquery.h
#pragma once
#include <string_view>
#include <string>
namespace csvquery {
    bool is_valid_schema(std::string_view name);
}
EOF
    cat << 'EOF' > /app/vendor/libcsvquery/csvquery.cpp
#include "csvquery.h"
#include <tuple>
namespace csvquery {
    bool is_valid_schema(std::string_view name) {
        auto [a, b] = std::make_tuple(1, 2); // C++17 structured binding
        return !name.empty();
    }
}
EOF
    cat << 'EOF' > /app/vendor/libcsvquery/Makefile
CXXFLAGS = -std=c++98 -O2
libcsvquery.a: csvquery.o
	ar rcs libcsvquery.a csvquery.o
csvquery.o: csvquery.cpp
	$(CXX) $(CXXFLAGS) -c csvquery.cpp
EOF

    # Create adversarial corpora
    mkdir -p /app/corpus/clean /app/corpus/evil

    # Clean 1
    cat << 'EOF' > /app/corpus/clean/01.json
{ "pipeline": [ { "$match": { "status": "active" } }, { "$lookup": { "from": "public_users", "localField": "id", "foreignField": "user_id", "as": "details" } } ] }
EOF

    # Clean 2
    cat << 'EOF' > /app/corpus/clean/02.json
{ "collection": "sales_data", "pipeline": [ { "$group": { "_id": "$region", "total": { "$sum": "$amount" } } } ] }
EOF

    # Evil 1 - Traversal
    cat << 'EOF' > /app/corpus/evil/01.json
{ "collection": "../etc/passwd", "pipeline": [ { "$match": {} } ] }
EOF

    # Evil 2 - Restricted schema
    cat << 'EOF' > /app/corpus/evil/02.json
{ "pipeline": [ { "$lookup": { "from": "private_keys", "as": "keys" } } ] }
EOF

    # Evil 3 - Arbitrary JS
    cat << 'EOF' > /app/corpus/evil/03.json
{ "pipeline": [ { "$match": { "$where": "function() { return true; }" } } ] }
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
