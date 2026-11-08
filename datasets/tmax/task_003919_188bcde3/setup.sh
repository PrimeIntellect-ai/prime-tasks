#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/model_exec.cpp
#include <iostream>
#include <string>

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cout << "0.1 0.2 0.3\n";
        return 0;
    }
    std::string input = argv[1];
    bool evil = (input.find("crypto") != std::string::npos ||
                 input.find("override") != std::string::npos ||
                 input.find("synergy") != std::string::npos);

    float x = 0.5f + (input.length() % 10) * 0.1f;
    float y = 0.2f + (input.length() % 5) * 0.1f;
    float z = 0.8f + (input.length() % 7) * 0.1f;

    if (evil) {
        x = -1.542f;
    }

    std::cout << x << " " << y << " " << z << "\n";
    return 0;
}
EOF
    g++ /tmp/model_exec.cpp -o /app/model_exec
    strip /app/model_exec
    rm /tmp/model_exec.cpp

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data/clean
    mkdir -p /home/user/data/evil

    cat << 'EOF' > /home/user/data/clean/clean1.csv
ID,Description
1,This is a normal dataset description.
2,Another clean row here.
EOF

    cat << 'EOF' > /home/user/data/clean/clean2.csv
ID,Description
1,Nothing to see here.
2,Just some text.
EOF

    cat << 'EOF' > /home/user/data/clean/clean3.csv
ID,Description
1,Data science is fun.
2,Machine learning models.
EOF

    cat << 'EOF' > /home/user/data/evil/evil1.csv
ID,Description
1,This is a normal dataset description.
2,We need more crypto in our lives.
EOF

    cat << 'EOF' > /home/user/data/evil/evil2.csv
ID,Description
1,Nothing to see here.
2,Let's override the system.
EOF

    cat << 'EOF' > /home/user/data/evil/evil3.csv
ID,Description
1,Data science is fun.
2,We must achieve synergy in our team.
EOF

    chmod -R 777 /home/user
