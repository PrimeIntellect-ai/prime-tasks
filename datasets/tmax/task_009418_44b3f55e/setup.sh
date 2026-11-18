#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make gcc sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/log_pipeline/data

    cat << 'EOF' > /home/user/log_pipeline/data/input.csv
ID,User,Bytes
1,alice,1500000000
2,bob,800000000
3,charlie,100000
EOF
    sed -i 's/$/\r/' /home/user/log_pipeline/data/input.csv

    cat << 'EOF' > /home/user/log_pipeline/process_logs.sh
#!/bin/bash
cd /home/user/log_pipeline

# Build the helper
make || exit 1

rm -f output.txt

# Parse input and process in parallel
tail -n +2 data/input.csv | while IFS=, read -r id user bytes; do
  # Simulate some work and write to output file concurrently
  # The multiple echoes create a race condition where output lines interleave
  (
    sleep 0.1
    echo -n "$id," >> output.txt
    echo -n "$user," >> output.txt
    echo "$bytes" >> output.txt
  ) &
done

wait

# Run aggregator
./aggregator < output.txt > summary.txt
EOF
    chmod +x /home/user/log_pipeline/process_logs.sh

    cat << 'EOF' > /home/user/log_pipeline/Makefile
CC=gcc-99
CFLAGS=-O2

aggregator: aggregator.c
	$(CC) $(CFLAGS) -o aggregator aggregator.c

clean:
	rm -f aggregator
EOF

    cat << 'EOF' > /home/user/log_pipeline/aggregator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char line[256];
    int total_bytes = 0;
    int count = 0;

    while (fgets(line, sizeof(line), stdin)) {
        char *id = strtok(line, ",");
        char *user = strtok(NULL, ",");
        char *bytes_str = strtok(NULL, ",");

        if (bytes_str) {
            total_bytes += atoi(bytes_str);
            count++;
        }
    }

    printf("Records Processed: %d\n", count);
    printf("Total Bytes: %d\n", total_bytes);
    return 0;
}
EOF

    chown -R user:user /home/user/log_pipeline
    chmod -R 777 /home/user
