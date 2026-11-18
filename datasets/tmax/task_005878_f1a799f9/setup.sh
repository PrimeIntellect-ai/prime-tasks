#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    git config --global user.email "test@example.com"
    git config --global user.name "Test User"

    mkdir -p /home/user/data_processor/src
    cd /home/user/data_processor
    git init

    cat << 'EOF' > generate_repo.py
import os
import subprocess

good_code = """#include <iostream>
#include <vector>
#include <thread>
#include <atomic>

std::atomic<long long> global_sum{0};

void worker(int start, int end) {
    for(int i=start; i<end; ++i) {
        global_sum += 1;
    }
}

int main() {
    global_sum = 0;
    std::vector<std::thread> threads;
    for(int i=0; i<10; ++i) {
        threads.emplace_back(worker, i*1000000, (i+1)*1000000);
    }
    for(auto& t : threads) {
        t.join();
    }
    std::cout << global_sum << std::endl;
    return 0;
}
"""

bad_code = """#include <iostream>
#include <vector>
#include <thread>
#include <atomic>

long long global_sum{0}; // BUG: missing std::atomic

void worker(int start, int end) {
    for(int i=start; i<end; ++i) {
        global_sum += 1;
    }
}

int main() {
    global_sum = 0;
    std::vector<std::thread> threads;
    for(int i=0; i<10; ++i) {
        threads.emplace_back(worker, i*1000000, (i+1)*1000000);
    }
    for(auto& t : threads) {
        t.join();
    }
    std::cout << global_sum << std::endl;
    return 0;
}
"""

for i in range(201):
    # Commits 0 to 85 are good.
    # Commit 86 introduces the race condition.
    if i < 86:
        current_code = good_code
    else:
        current_code = bad_code

    # Commits 120 to 135 have a compile error (undeclared function).
    if 120 <= i <= 135:
        current_code = current_code.replace("return 0;", "undeclared_function();\n    return 0;")

    # Append a dummy comment to ensure the commit hash changes
    current_code += f"\n// Iteration {i}\n"

    with open("src/processor.cpp", "w") as f:
        f.write(current_code)

    subprocess.run(["git", "add", "src/processor.cpp"], check=True)
    subprocess.run(["git", "commit", "-m", f"Refactor data handler phase {i}"], check=True)

# Save the exact bad commit hash for verification
bad_commit_hash = subprocess.check_output(["git", "log", "--format=%H", "-n", "1", "--skip=114"]).decode("utf-8").strip()
with open("/tmp/expected_bad_commit.txt", "w") as f:
    f.write(bad_commit_hash)

EOF

    python3 generate_repo.py
    rm generate_repo.py

    chmod -R 777 /home/user
