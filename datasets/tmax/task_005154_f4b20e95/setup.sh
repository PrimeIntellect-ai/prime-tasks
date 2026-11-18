#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang-go file
    pip3 install pytest hypothesis

    mkdir -p /home/user/src
    mkdir -p /home/user/artifacts

    cat << 'EOF' > /home/user/src/processor.c
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 2) return 0;
#ifdef ENABLE_REVERSE
    int len = strlen(argv[1]);
    for(int i=len-1; i>=0; i--) {
        putchar(argv[1][i]);
    }
#else
    // Fallback incorrect behavior if flag is missing
    printf("%s", argv[1]);
#endif
    return 0;
}
EOF

    cat << 'EOF' > /home/user/src/processor.go
package main

import (
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		return
	}
	s := os.Args[1]
	r := []rune(s)
	for i, j := 0, len(r)-1; i < j; i, j = i+1, j-1 {
		r[i], r[j] = r[j], r[i]
	}
	fmt.Print(string(r))
}
EOF

    cat << 'EOF' > /home/user/src/test_props.py
import subprocess
from hypothesis import given, settings
import hypothesis.strategies as st
import sys

@given(st.text(alphabet="abcdefghijklmnopqrstuvwxyz0123456789", min_size=1, max_size=50))
@settings(max_examples=100)
def test_processors_match(input_str):
    # TODO: Implement subprocess calls to both binaries and assert their stdout is equal
    pass

if __name__ == "__main__":
    test_processors_match()
    with open("/home/user/artifacts/test_report.txt", "w") as f:
        f.write("PROPERTY TESTS PASSED\n")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
