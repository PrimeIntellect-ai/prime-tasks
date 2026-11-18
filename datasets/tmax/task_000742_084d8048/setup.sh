#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app /test_data/evil /test_data/clean

    cat << 'EOF' > /app/legacy_filter.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char line[1024];
    int depth = 0;
    while (fgets(line, sizeof(line), f)) {
        if (strstr(line, "import") != NULL) {
            if (strstr(line, "\"../") != NULL || strstr(line, "\"/") != NULL) return 1;
        }
        if (strstr(line, "service Admin") != NULL || strstr(line, "service System") != NULL) return 1;

        for (int i=0; line[i]; i++) {
            if (line[i] == '{') depth++;
            if (line[i] == '}') depth--;
        }
        if (depth >= 3) {
            return 1;
        }
    }
    fclose(f);
    return 0;
}
EOF

    gcc -O2 /app/legacy_filter.c -o /app/legacy_filter
    strip /app/legacy_filter
    rm /app/legacy_filter.c

    cat << 'EOF' > /test_data/clean/1.proto
syntax = "proto3";
import "google/protobuf/empty.proto";
service UserService {
  rpc GetUser (google.protobuf.Empty) returns (google.protobuf.Empty);
}
message Outer {
  message Inner {
    string id = 1;
  }
}
EOF

    cat << 'EOF' > /test_data/evil/1.proto
syntax = "proto3";
import "../secret.proto";
EOF

    cat << 'EOF' > /test_data/evil/2.proto
syntax = "proto3";
import "/etc/passwd";
EOF

    cat << 'EOF' > /test_data/evil/3.proto
syntax = "proto3";
service Admin {
}
EOF

    cat << 'EOF' > /test_data/evil/4.proto
syntax = "proto3";
message A {
  message B {
    message C {
      string id = 1;
    }
  }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
