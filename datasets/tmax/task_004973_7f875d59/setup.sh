#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gcc-aarch64-linux-gnu golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/gateway/tests

    cat << 'EOF' > /home/user/gateway/urldecode.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

char* decode_url(const char *input) {
    if (!input) return NULL;
    int len = strlen(input);
    // BUG: Allocating exact length without null terminator space if no % is present, 
    // or under-allocating if % is at the end.
    char *output = malloc(len); 
    int i = 0, j = 0;
    while (i < len) {
        if (input[i] == '%') {
            // BUG: Doesn't check bounds for i+1 and i+2
            char hex[3] = {input[i+1], input[i+2], '\0'};
            output[j++] = (char)strtol(hex, NULL, 16);
            i += 3;
        } else {
            output[j++] = input[i++];
        }
    }
    output[j] = '\0';
    return output;
}
EOF

    cat << 'EOF' > /home/user/gateway/main.c
#include <stdio.h>
#include <stdlib.h>
#include "urldecode.c"

int main(int argc, char **argv) {
#ifndef SECURE_MODE
    printf("INSECURE\n");
    return 1;
#endif
    if (argc < 2) return 0;
    char *decoded = decode_url(argv[1]);
    if (decoded) {
        printf("%s\n", decoded);
        free(decoded);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/gateway/tests/stress.go
package main

import (
	"fmt"
	"os/exec"
)

func main() {
	payloads := []string{"hello%20world", "test%2Fpath", "malicious%00byte", "incomplete%"}
	success := true
	for i := 0; i < 10; i++ {
		cmd := exec.Command("../build/gateway_amd64", payloads[i%len(payloads)])
		err := cmd.Run()
		if err != nil {
			success = false
		}
	}
	if success {
		fmt.Println("PASS")
	} else {
		fmt.Println("FAIL")
	}
}
EOF

    chmod -R 777 /home/user
