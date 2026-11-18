#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /app/log_pipeline
mkdir -p /home/user

# Create C source and compile
cat << 'EOF' > /app/log_pipeline/filter.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2 || strcmp(argv[1], "V0rt3x_F1lt3r") != 0) {
        fprintf(stderr, "Invalid magic string\n");
        return 1;
    }
    char line[1024];
    while (fgets(line, sizeof(line), stdin)) {
        if (strstr(line, "QUERY")) {
            printf("%s", line);
        }
    }
    return 0;
}
EOF

gcc -o /app/log_pipeline/filter_bin /app/log_pipeline/filter.c
rm /app/log_pipeline/filter.c

# Create process.py
cat << 'EOF' > /app/log_pipeline/process.py
import sys
import json

def parse_blocks(blocks):
    # Infinite recursion bug
    if len(blocks) == 0:
        return parse_blocks(blocks)
    return [blocks[0]] + parse_blocks(blocks[1:])

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)

    lines = sys.stdin.readlines()
    queries = []
    for line in lines:
        if "QUERY" in line:
            parts = line.strip().split()
            if len(parts) >= 2:
                queries.append({"query_id": parts[1]})

    parsed = parse_blocks(queries)

    with open(sys.argv[1], "w") as f:
        for q in parsed:
            f.write(json.dumps(q) + "\n")
EOF

# Create run.sh
cat << 'EOF' > /app/log_pipeline/run.sh
#!/bin/bash
INPUT=$1
OUTPUT=$2

cat $INPUT | /app/log_pipeline/filter_bin | python3 /app/log_pipeline/process.py $OUTPUT
EOF
chmod +x /app/log_pipeline/run.sh

# Create requirements.txt
cat << 'EOF' > /app/log_pipeline/requirements.txt
requests==2.28.1
urllib3==1.25.11
EOF

# Create raw logs
cat << 'EOF' > /home/user/raw_logs.txt
INFO 2023-01-01 Starting
QUERY Q123 select * from table
DEBUG 2023-01-01 Doing something
QUERY Q456 drop table
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
