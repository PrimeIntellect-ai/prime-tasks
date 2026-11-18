#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc time
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sensor_data.csv
id,sensor_val,timestamp
1,45.1,1620000001
2,46.2,1620000002
3,55.0,1620000003
4,44.9,1620000004
5,30.1,1620000005
6,47.8,1620000006
7,45.5,1620000007
8,53.6,1620000008
9,37.5,1620000009
10,48.0,1620000010
EOF

    cat << 'EOF' > /home/user/filter.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
// Missing math.h for fabs

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <mean> <stddev>\n", argv[0]);
        return 1;
    }

    float mean = atof(argv[1]);
    float stddev = atof(argv[2]);

    char line[1024];
    int is_header = 1;

    while (fgets(line, sizeof(line), stdin)) {
        if (is_header) {
            printf("%s", line);
            is_header = 0;
            continue;
        }

        char line_copy[1024];
        strcpy(line_copy, line);

        char *tok = strtok(line_copy, ",");
        tok = strtok(NULL, ","); // Get second column

        if (tok != NULL) {
            // BUG: Using atoi instead of atof, and abs instead of fabs
            int val = atoi(tok);
            float z = abs(val - mean) / stddev;

            if (z <= 2.5) {
                printf("%s", line);
            }
        }
    }
    return 0;
}
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
