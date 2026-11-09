#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/project
    mkdir -p /home/user/data

    # Create data files, including one with spaces
    echo "Hello from file1" > /home/user/data/file1.txt
    echo "Hello from file 2" > "/home/user/data/file 2.txt"

    # Create the broken C++ processor
    cat << 'EOF' > /home/user/project/processor.cpp
#include <iostream>
#include <fstream>
#include <string>

void processFile(const std::string& filename, int retries = 0) {
    std::ifstream file(filename);
    if (!file.is_open()) {
        // BUG: Infinite recursion here. Missing termination condition.
        processFile(filename, retries + 1);
        return;
    }

    std::string line;
    while(std::getline(file, line)) {
        std::cout << filename << ": " << line << "\n";
    }
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <filename>\n";
        return 1;
    }
    processFile(argv[1]);
    return 0;
}
EOF

    # Compile the broken version initially
    cd /home/user/project
    g++ processor.cpp -o processor

    # Create the broken bash script
    cat << 'EOF' > /home/user/project/run_all.sh
#!/bin/bash
cd /home/user/project
for file in /home/user/data/*; do
  # BUG: Missing quotes around $file
  ./processor $file
done
EOF
    chmod +x /home/user/project/run_all.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
