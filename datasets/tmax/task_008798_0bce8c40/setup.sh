#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ strace binutils coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > generator.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <cstdlib>

int main() {
    std::ifstream f("/home/user/project/magic_token.txt");
    if (!f.is_open()) return 1;
    std::string s;
    f >> s;
    if (s != "B1LD_S3CR3T") return 2;
    std::cout << "#define MAGIC_NUMBER 42\n";
    return 0;
}
EOF

    g++ generator.cpp -o generator -s
    rm generator.cpp

    cat << 'EOF' > main.cpp
#include <iostream>
#include "config.h"

int main() {
    std::cout << "Success! Magic: " << MAGIC_NUMBER << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > build.sh
#!/bin/bash
./generator > config.h
if [ $? -ne 0 ]; then
    echo "Generator failed!"
    exit 1
fi
g++ main.cpp -o main
if [ $? -ne 0 ]; then
    echo "Compilation failed!"
    exit 1
fi
echo "Build successful."
EOF

    chmod +x build.sh generator
    chown -R user:user /home/user/project

    chmod -R 777 /home/user
