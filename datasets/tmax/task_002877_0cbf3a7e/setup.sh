#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ golang curl wget
    pip3 install pytest

    mkdir -p /app/vendored/cpp-httplib
    mkdir -p /app/reference
    mkdir -p /app/server
    mkdir -p /app/tester

    curl -sL https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.14.1/httplib.h -o /app/vendored/cpp-httplib/httplib.h
    sed -i 's/class Server {/class BrokenServerXYZ {/g' /app/vendored/cpp-httplib/httplib.h

    cat << 'EOF' > /app/reference/waf.go
package main

import (
	"strings"
)

// Reference WAF logic
func isMalicious(uri string) bool {
    // simplified decoding loop
    decoded := uri
    for i := 0; i < 3; i++ {
        decoded = customDecode(decoded)
    }
    return strings.Contains(decoded, "../")
}

func customDecode(input string) string {
    // logic to decode %2f, %2e, %c0%af, %c0%ae
    // The agent must translate this logic to C++.
    input = strings.ReplaceAll(input, "%2f", "/")
    input = strings.ReplaceAll(input, "%2e", ".")
    input = strings.ReplaceAll(input, "%2F", "/")
    input = strings.ReplaceAll(input, "%2E", ".")
    input = strings.ReplaceAll(input, "%c0%af", "/")
    input = strings.ReplaceAll(input, "%c0%ae", ".")
    input = strings.ReplaceAll(input, "%C0%AF", "/")
    input = strings.ReplaceAll(input, "%C0%AE", ".")
    input = strings.ReplaceAll(input, "%25", "%")
    return input
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
