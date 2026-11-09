#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc gcc tar gzip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/research_data/subset_1
    mkdir -p /home/user/research_data/subset_2
    mkdir -p /app

    # Create log_scorer binary
    cat << 'EOF' > /tmp/log_scorer.c
#include <stdio.h>

int main() {
    int c;
    int count = 0;
    while ((c = getchar()) != EOF) {
        if (c == 'A' || c == 'E' || c == 'I' || c == 'O' || c == 'U') {
            count++;
        }
    }
    if (count >= 5) printf("85\n");
    else if (count >= 1) printf("50\n");
    else printf("10\n");
    return 0;
}
EOF
    gcc -O2 /tmp/log_scorer.c -o /app/log_scorer
    rm /tmp/log_scorer.c

    # Create test log files and tar archives
    cat << 'EOF' > /tmp/test1.log
THIS RECORD HAS FIVE VOWELS A E I O U
---END_RECORD---
this record has none
---END_RECORD---
ANOTHER RECORD WITH A E I O U
EOF

    cat << 'EOF' > /tmp/test2.log
JUST A NORMAL RECORD A E I O U
---END_RECORD---
SHORT
EOF

    # Pack into tar.gz
    cd /tmp
    tar -czf archive1.tar.gz test1.log
    tar -czf archive2.tar.gz test2.log

    mv archive1.tar.gz /home/user/research_data/subset_1/
    mv archive2.tar.gz /home/user/research_data/subset_2/
    rm test1.log test2.log

    # Create a broken symlink
    ln -s /does/not/exist.log /home/user/research_data/subset_1/broken_link.log

    # Create user
    useradd -m -s /bin/bash user || true

    # Fix permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user
