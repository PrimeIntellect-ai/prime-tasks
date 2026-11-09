#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    # Create PR codebase
    mkdir -p /home/user/resolver_pr
    echo "// parser.cpp" > /home/user/resolver_pr/parser.cpp
    echo "// semver.cpp" > /home/user/resolver_pr/semver.cpp

    # Create hidden test graphs
    mkdir -p /app/hidden_test_graphs
    for i in {1..50}; do
        echo "PKG App$i 1.0.0" > /app/hidden_test_graphs/graph_$i.txt
    done

    # Create legacy resolver binary
    cat << 'EOF' > /tmp/legacy_resolver.cpp
#include <iostream>
#include <unistd.h>

int main(int argc, char** argv) {
    usleep(100000); // Artificial delay to make it slow
    std::cout << "UNSATISFIABLE\n";
    return 0;
}
EOF
    mkdir -p /app
    g++ -O3 /tmp/legacy_resolver.cpp -o /app/legacy_resolver
    strip /app/legacy_resolver
    rm /tmp/legacy_resolver.cpp

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
