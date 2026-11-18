#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/test_stability.go
package main

import (
	"fmt"
)

func main() {
	x := 4.0
	lr := 0.1
	iterations := 1000

	for i := 0; i < iterations; i++ {
		// Calculate gradient of f(x) = x^4 - 3x^3 + 2
		// df/dx = 4x^3 - 9x^2
		grad := 4*(x*x*x) - 9*(x*x)

		// Update x
		x = x - lr*grad
	}

	fmt.Printf("Final x: %f\n", x)
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
