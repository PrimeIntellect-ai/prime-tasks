#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest pandas

    mkdir -p /home/user/etl_pipeline
    cd /home/user/etl_pipeline

    cat << 'EOF' > filter.c
#include <stdio.h>
#include <stdint.h>

int main() {
    char line[256];
    // Skip header
    if (!fgets(line, sizeof(line), stdin)) return 0;
    printf("id,value\n");

    while (fgets(line, sizeof(line), stdin)) {
        float id_float;
        double value;
        // BUG: Parsing ID as a 32-bit float causes precision loss for large integers
        if (sscanf(line, "%f,%lf", &id_float, &value) == 2) {
            uint64_t id = (uint64_t)id_float;
            if (value > 20.0) {
                printf("%llu,%.1f\n", (unsigned long long)id, value);
            }
        }
    }
    return 0;
}
EOF

    cat << 'EOF' > Makefile
all: filter

filter: filter.c
	gcc -O2 -Wall filter.c -o filter

clean:
	rm -f filter
EOF

    cat << 'EOF' > data.csv
id,value
20000001,50.5
20000002,10.0
20000003,99.9
20000004,25.0
20000005,19.9
EOF

    cat << 'EOF' > validate.py
import sys
import pandas as pd

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 validate.py <output.csv>")
        sys.exit(1)

    try:
        df = pd.read_csv(sys.argv[1])
    except Exception as e:
        print(f"FAIL: Could not read CSV - {e}")
        sys.exit(1)

    expected_ids = [20000001, 20000003, 20000004]
    expected_values = [50.5, 99.9, 25.0]

    if list(df['id']) == expected_ids and list(df['value']) == expected_values:
        print("PASS")
    else:
        print(f"FAIL: Data mismatch.\nExpected IDs: {expected_ids}\nGot: {list(df['id'])}")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/etl_pipeline
    chmod -R 777 /home/user
