#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pipeline
    mkdir -p /home/user/uploads

    cat << 'EOF' > /home/user/pipeline/parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    char magic[4];
    if (fread(magic, 1, 4, f) != 4) {
        fclose(f);
        return 1;
    }

    if (strncmp(magic, "LOG1", 4) != 0) {
        printf("Invalid magic in %s\n", argv[1]);
        fclose(f);
        return 1;
    }

    int n;
    if (fread(&n, sizeof(int), 1, f) != 1) {
        fclose(f);
        return 1;
    }

    // BUG: Missing validation for n
    char *data = malloc(n * 16);

    // BUG: Segfaults if malloc returns NULL (e.g. n is negative and size overflows)
    fread(data, 16, n, f);

    printf("Processed %d records from %s\n", n, argv[1]);
    free(data);
    fclose(f);
    return 0;
}
EOF

    gcc -o /home/user/pipeline/parser /home/user/pipeline/parser.c

    cat << 'EOF' > /home/user/pipeline/process_logs.sh
#!/bin/bash
# Bug: breaks on spaces
for file in $(ls /home/user/uploads/*.log); do
    /home/user/pipeline/parser "$file" >> /home/user/pipeline/results.txt 2>>/home/user/pipeline/error.log
done
EOF
    chmod +x /home/user/pipeline/process_logs.sh

    python3 -c 'import struct; f=open("/home/user/uploads/valid1.log", "wb"); f.write(b"LOG1" + struct.pack("<i", 2) + b"A"*32); f.close()'
    python3 -c 'import struct; f=open("/home/user/uploads/file with spaces.log", "wb"); f.write(b"LOG1" + struct.pack("<i", 3) + b"B"*48); f.close()'
    python3 -c 'import struct; f=open("/home/user/uploads/corrupt.log", "wb"); f.write(b"LOG1" + struct.pack("<i", -1) + b"C"*16); f.close()'
    python3 -c 'import struct; f=open("/home/user/uploads/massive.log", "wb"); f.write(b"LOG1" + struct.pack("<i", 50000) + b"D"*16); f.close()'

    chown -R user:user /home/user/pipeline /home/user/uploads
    chmod -R 777 /home/user
