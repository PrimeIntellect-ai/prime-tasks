#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang jq tar coreutils libc6-dev
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    # Create generator.c
    cat << 'EOF' > generator.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int count = atoi(argv[1]);
    for (int i = 0; i < count; i++) {
        printf("%d\n", i);
    }
    return 0;
}
EOF

    # Create processor.go
    cat << 'EOF' > processor.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
)

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	sum := int64(0)
	for scanner.Scan() {
		val, _ := strconv.ParseInt(scanner.Text(), 10, 64)
		sum += val
	}
	fmt.Println(sum)
}
EOF

    # Create config.json
    cat << 'EOF' > config.json
{
  "runs": 5,
  "count": 500000
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/project
    chmod -R 777 /home/user
