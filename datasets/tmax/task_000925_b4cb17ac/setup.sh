#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest packaging

    # Create /app/legacy_resolver
    mkdir -p /app
    cat << 'EOF' > /app/legacy_resolver.cpp
#include <iostream>
#include <string>
#include <cstdlib>

int main(int argc, char** argv) {
    if (argc < 3) return 1;
    std::string expr = argv[1];
    std::string ver = argv[2];

    // Stub implementation for initial state
    return 0;
}
EOF
    g++ -O3 -s /app/legacy_resolver.cpp -o /app/legacy_resolver
    chmod +x /app/legacy_resolver

    # Create qa_project
    mkdir -p /home/user/qa_project/qa_project
    touch /home/user/qa_project/qa_project/__init__.py

    cat << 'EOF' > /home/user/qa_project/pyproject.toml
[build-system]
requires = [setuptools]
build-backend = "setuptools.build_meta"

[project]
name = "qa_project"
version = 1.0.0
dependencies = [
    requests
]
EOF

    cat << 'EOF' > /home/user/qa_project/run_e2e_tests.sh
#!/bin/bash
/app/legacy_resolver ">=1.0.0" "1.2.3"
EOF
    chmod +x /home/user/qa_project/run_e2e_tests.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
