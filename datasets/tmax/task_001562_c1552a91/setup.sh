#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git g++
    pip3 install pytest

    mkdir -p /home/user/data_processor
    cd /home/user/data_processor

    git config --global user.email "test@example.com"
    git config --global user.name "Test User"

    # 1. Setup Git Repository and Secret
    git init
    echo "# Data Processor" > README.md
    echo 'const char* WAL_SECRET = "x9F2kL_pQ8zV1";' > config.h
    git add README.md config.h
    git commit -m "Initial commit with config"

    # Remove the secret
    echo "// WAL_SECRET moved to env vars" > config.h
    git add config.h
    git commit -m "Security: remove hardcoded WAL secret"

    # 2. Setup broken C++ recovery tool and build script
    cat << 'EOF' > recovery.cpp
#include <iostream>
#include <string>
#include <thread>
#include <vector>

void dummy_worker() {
    // just a dummy thread function
}

int main(int argc, char* argv[]) {
    if (argc != 3) {
        std::cerr << "Usage: " << argv[0] << " <key> <wal_file>" << std::endl;
        return 1;
    }

    std::string key = argv[1];
    std::string file = argv[2];

    if (key != "x9F2kL_pQ8zV1") {
        std::cerr << "FATAL: Invalid decryption key." << std::endl;
        return 1;
    }

    // Simulate multithreaded recovery
    std::vector<std::thread> workers;
    for(int i=0; i<2; ++i) {
        workers.push_back(std::thread(dummy_worker));
    }

    for(auto& t : workers) {
        t.join();
    }

    std::cout << "SUCCESS: Recovered WAL. Last Committed TXN_ID=7734190" << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > build.sh
#!/bin/bash
# Missing -pthread flag which will cause a linker error with std::thread
g++ recovery.cpp -o recovery
EOF
    chmod +x build.sh

    # 3. Create mock WAL file
    echo "BINARY_WAL_DATA_MOCK_123456" > system.wal

    # 4. Create mock core dump
    dd if=/dev/urandom of=core.dump bs=1K count=1024 2>/dev/null
    echo "DEADLOCK_TX_HASH=A8F93B2C9E1045F1" >> core.dump
    dd if=/dev/urandom bs=1K count=10 >> core.dump 2>/dev/null

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
