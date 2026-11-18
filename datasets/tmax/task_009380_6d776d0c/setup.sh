#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git build-essential
    pip3 install pytest

    mkdir -p /home/user/ticket_1092/repo
    mkdir -p /home/user/ticket_1092/attachments
    cd /home/user/ticket_1092/repo

    git init
    git config user.name "QA Dev"
    git config user.email "qa@example.com"

    # Create Makefile
    cat << 'EOF' > Makefile
aggregator: aggregator.cpp
	g++ -O0 -g aggregator.cpp -o aggregator
clean:
	rm -f aggregator
EOF

    # Commit 1: Good commit
    cat << 'EOF' > aggregator.cpp
#include <iostream>
#include <fstream>
#include <string>

void process_header(const std::string& line) {
    // Basic processing
}

void parse_logs(const std::string& filename) {
    std::ifstream file(filename);
    std::string line;
    while(std::getline(file, line)) {
        process_header(line);
    }
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    parse_logs(argv[1]);
    return 0;
}
EOF

    export GIT_COMMITTER_DATE="2023-10-01T10:00:00"
    export GIT_AUTHOR_DATE="2023-10-01T10:00:00"
    git add Makefile aggregator.cpp
    git commit -m "Initial commit"

    # Commit 2: Refactor
    export GIT_COMMITTER_DATE="2023-10-02T10:00:00"
    export GIT_AUTHOR_DATE="2023-10-02T10:00:00"
    sed -i 's/Basic processing/Basic processing updated/' aggregator.cpp
    git add aggregator.cpp
    git commit -m "Update processing comment"

    # Commit 3: Introduce the bug
    cat << 'EOF' > aggregator.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <cstdlib>

bool in_transaction = false;

void extract_metrics(const std::string& line) {
    if (line.find("METRIC_CRITICAL") != std::string::npos) {
        if (!in_transaction) {
            std::cerr << "Fatal error: Critical metric outside transaction" << std::endl;
            abort(); // THE CRASH
        }
    }
}

void process_header(const std::string& line) {
    if (line == "BEGIN_TRANSACTION") {
        in_transaction = true;
    } else if (line == "END_TRANSACTION") {
        in_transaction = false;
    }
    extract_metrics(line);
}

void parse_logs(const std::string& filename) {
    std::ifstream file(filename);
    std::string line;
    while(std::getline(file, line)) {
        process_header(line);
    }
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    parse_logs(argv[1]);
    return 0;
}
EOF

    export GIT_COMMITTER_DATE="2023-10-03T10:00:00"
    export GIT_AUTHOR_DATE="2023-10-03T10:00:00"
    git add aggregator.cpp
    git commit -m "Add metric extraction logic"
    BUGGY_COMMIT=$(git rev-parse HEAD)

    # Commit 4: Unrelated change
    export GIT_COMMITTER_DATE="2023-10-04T10:00:00"
    export GIT_AUTHOR_DATE="2023-10-04T10:00:00"
    echo "// End of file" >> aggregator.cpp
    git add aggregator.cpp
    git commit -m "Add EOF comment"

    # Create large payload
    cd /home/user/ticket_1092/attachments
    for i in $(seq 1 9999); do
        echo "INFO: Normal log line $i" >> large_payload.txt
        if [ "$i" -eq 4500 ]; then
            echo "END_TRANSACTION" >> large_payload.txt
        fi
        if [ "$i" -eq 8200 ]; then
            echo "METRIC_CRITICAL=99" >> large_payload.txt
        fi
    done

    # Save the deterministic hash for verifier
    echo $BUGGY_COMMIT > /tmp/buggy_hash.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
