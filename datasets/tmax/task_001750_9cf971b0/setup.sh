#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ make
pip3 install pytest

mkdir -p /home/user/project/src
mkdir -p /home/user/project/data
mkdir -p /home/user/project/logs

cat << 'EOF' > /home/user/project/src/decoder.cpp
#include <iostream>
#include <fstream>
#include <string>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    std::ifstream file(argv[1], std::ios::binary);
    if (!file) return 1;

    while (file.peek() != EOF) {
        int len = file.get();
        if (len == EOF) break;
        std::string s;
        // BUG: Reads len bytes instead of len UTF-8 characters
        for (int i = 0; i < len; ++i) {
            int c = file.get();
            if (c == EOF) break;
            s += (char)c;
        }
        std::cout << "Read: " << s << std::endl;
    }
    return 0;
}
EOF

cat << 'EOF' > /home/user/project/Makefile
test: src/decoder.cpp
	g++ -o decoder src/decoder.cpp
	./decoder data/input.dat > output.txt
EOF

cat << 'EOF' > /home/user/project/logs/service_a.log
[2023-10-24 10:00:00] INFO: Service A starting.
[2023-10-24 10:00:05] INFO: Connecting to downstream consumers.
[2023-10-24 10:01:00] UPDATE: Migrated to protocol v2. 
[2023-10-24 10:01:00] NOTE: String length prefixes (1-byte) now represent the number of UTF-8 characters, not the number of bytes!
[2023-10-24 10:05:00] INFO: Dispatched test batch.
EOF

python3 -c "
with open('/home/user/project/data/input.dat', 'wb') as f:
    f.write(bytes([5]) + b'Hello')
    f.write(bytes([3]) + b'C++')
    f.write(bytes([4]) + 'Café'.encode('utf-8'))
    f.write(bytes([5]) + b'World')
"

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/project
chmod -R 777 /home/user
