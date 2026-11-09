#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ci_logs
    mkdir -p /home/user/project/src
    mkdir -p /home/user/project/data
    mkdir -p /home/user/project/build

    cat << 'EOF' > /home/user/ci_logs/container_build.log
[INFO] Container initialization...
[INFO] Fetching source code...
[INFO] Starting build script...
[INFO] Compiling codegen tool...
[INFO] Running codegen on data/config.txt -> build/config.h
[INFO] Compiling main application...
In file included from src/main.cpp:2:
build/config.h:4:9: error: macro names must be identifiers
    4 | #define # Database configuration # Database configuration
      |         ^
build/config.h:5:9: error: macro names must be identifiers
    5 | #define 
      |         ^
make: *** [Makefile:12: main.o] Error 1
[ERROR] Build failed with exit code 2.
EOF

    cat << 'EOF' > /home/user/project/data/config.txt
APP_NAME=MyApp
APP_PORT=8080

# Database configuration
DB_HOST=localhost
DB_USER=admin
EOF

    cat << 'EOF' > /home/user/project/src/codegen.cpp
#include <iostream>
#include <fstream>
#include <string>

int main(int argc, char* argv[]) {
    if (argc != 3) {
        std::cerr << "Usage: codegen <input_file> <output_file>\n";
        return 1;
    }

    std::ifstream infile(argv[1]);
    std::ofstream outfile(argv[2]);

    if (!infile || !outfile) {
        std::cerr << "Error opening files.\n";
        return 1;
    }

    outfile << "// AUTO-GENERATED CONFIGURATION\n";
    outfile << "#pragma once\n\n";

    std::string line;
    while (std::getline(infile, line)) {
        // BUG: Does not check for empty lines or comments
        size_t pos = line.find('=');
        std::string key = line.substr(0, pos);
        std::string val = line.substr(pos + 1);
        outfile << "#define " << key << " \"" << val << "\"\n";
    }

    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/src/main.cpp
#include <iostream>
#include "../build/config.h"

int main() {
    std::cout << "Application: " << APP_NAME << "\n";
    std::cout << "Port: " << APP_PORT << "\n";
    std::cout << "Database Host: " << DB_HOST << "\n";
    std::cout << "Database User: " << DB_USER << "\n";
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/build.sh
#!/bin/bash

cd /home/user/project

echo "Building codegen..."
g++ src/codegen.cpp -o build/codegen

echo "Generating config.h..."
build/codegen data/config.txt build/config.h

echo "Building app..."
g++ src/main.cpp -o build/app

echo "Build successful."
EOF

    chmod +x /home/user/project/build.sh
    chmod -R 777 /home/user
