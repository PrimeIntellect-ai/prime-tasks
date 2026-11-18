#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc patch
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/peer_resolver.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <graph> <manifest>\n", argv[0]);
        return 1;
    }

    // Read the second file to get its content for the diff (simplified for the oracle)
    printf("--- a/manifest\n");
    printf("+++ b/manifest\n");
    printf("@@ -1,2 +1,3 @@\n");
    printf(" {\n");
    printf("+  \"dependencies_resolved\": true,\n");
    printf("   \"name\": \"mobile-app\"\n");

    return 0;
}
EOF
    gcc -O3 -s /tmp/peer_resolver.c -o /app/peer_resolver
    chmod +x /app/peer_resolver

    echo -n "dummy_binary_graph_data" > /app/sample_graph.bin
    cat << 'EOF' > /app/sample_manifest.json
{
  "name": "mobile-app"
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
