#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc strace coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project
    mkdir -p /home/user/inputs

    python3 -c "
import os
for i in range(50):
    filename = f'/home/user/inputs/input_{i:03d}.dat'
    if i == 37:
        with open(filename, 'w') as f:
            f.write('A' * 120)
    else:
        with open(filename, 'wb') as f:
            f.write(os.urandom(16))
"

    cat << 'EOF' > /home/user/project/data_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

void parse_record(const char *filename) {
    char buffer[64];
    int fd = open(filename, O_RDONLY);
    if (fd < 0) return;

    // VULNERABILITY: reading up to 128 bytes into a 64 byte buffer
    read(fd, buffer, 128);
    close(fd);

    if (buffer[0] == 'X') {
        printf("Record marked X\n");
    }
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    parse_record(argv[1]);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/test_all.sh
#!/bin/bash
gcc -o data_parser data_parser.c -fno-stack-protector
if [ $? -ne 0 ]; then
    echo "Build failed"
    exit 1
fi

for f in /home/user/inputs/*.dat; do
    ./data_parser "$f" > /dev/null 2>&1
    if [ $? -eq 139 ]; then
        echo "Test failed on an input."
        exit 1
    fi
done

echo "All tests passed!"
touch /home/user/project/pass.flag
EOF

    chmod +x /home/user/project/test_all.sh
    chmod -R 777 /home/user
