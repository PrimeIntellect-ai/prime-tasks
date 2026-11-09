#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc coreutils
    pip3 install pytest

    mkdir -p /home/user/pkg-mgr
    cd /home/user/pkg-mgr

    cat << 'EOF' > graph.txt
417070: 4c696241 4c696242
4c696241: 436f7265
4c696242: 436f7265
436f7265: 
5374616e64616c6f6e65: 
EOF

    cat << 'EOF' > decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char hex[1024];
    if (scanf("%1023s", hex) != 1) return 1;
    // BUG: The sscanf reads beyond 2 chars if not careful, and misses the newline.
    // Also using strlen in loop condition is inefficient but mostly it's the sscanf format
    // A correct fix: char buf[3] = {0}; for loop...
    for (int i = 0; i < strlen(hex); i += 2) {
        int val;
        // BUG: %x consumes all available hex digits, not just 2.
        sscanf(&hex[i], "%x", &val);
        printf("%c", val);
    }
    printf("\n");
    return 0;
}
EOF

    cat << 'EOF' > resolve.sh
#!/bin/bash
# BUG: Missing compilation step for decoder.c
# gcc -o decoder decoder.c

> edges.txt
while read -r line; do
    # Skip empty lines
    [ -z "$line" ] && continue

    parent=$(echo "$line" | cut -d: -f1)
    deps=$(echo "$line" | cut -d: -f2)

    dec_parent=$(echo "$parent" | ./decoder)

    # BUG: If deps is empty, this loop doesn't run and the parent is lost from the graph.
    # BUG: The edge direction is backwards for a build order.
    for dep in $deps; do
        dec_dep=$(echo "$dep" | ./decoder)
        echo "$dec_parent $dec_dep" >> edges.txt
    done
done < "$1"

# Output to build_order.txt
tsort edges.txt > /home/user/build_order.txt
EOF

    chmod +x resolve.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
