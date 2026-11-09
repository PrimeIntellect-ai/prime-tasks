#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go curl
    pip3 install pytest

    mkdir -p /home/user/logs
    mkdir -p /home/user/pricing-engine

    cat << 'EOF' > /home/user/logs/api-gateway.log
[2023-10-27T03:00:01Z] INFO tx_id=A101 method=GET path=/calculate?rate=0.5 status=200
[2023-10-27T03:00:05Z] INFO tx_id=A102 method=GET path=/calculate?rate=1.2 status=200
[2023-10-27T03:00:12Z] INFO tx_id=A103 method=GET path=/calculate?rate=0.3333333 status=504
[2023-10-27T03:00:15Z] INFO tx_id=A104 method=GET path=/calculate?rate=0.8 status=504
EOF

    cat << 'EOF' > /home/user/logs/pricing-engine.log
[2023-10-27T03:00:03Z] DEBUG tx_id=A101 msg="Started calculating yield"
[2023-10-27T03:00:03Z] DEBUG tx_id=A101 msg="Finished calculating yield"
[2023-10-27T03:00:07Z] DEBUG tx_id=A102 msg="Started calculating yield"
[2023-10-27T03:00:07Z] DEBUG tx_id=A102 msg="Finished calculating yield"
[2023-10-27T03:00:14Z] DEBUG tx_id=A103 msg="Started calculating yield"
EOF

    cat << 'EOF' > /home/user/pricing-engine/main.go
package main

import (
	"fmt"
	"net/http"
	"strconv"
)

// CalculateYield uses a numerical method to find the root.
// BUG: Uses float32 which lacks the precision to reach a diff < 1e-8 for certain values like 1/3, causing an infinite loop.
func CalculateYield(rate float32) float32 {
	var current float32 = rate
	for {
		// Dummy Newton-Raphson step: f(x) = x^2 - rate, f'(x) = 2x
		// x_{n+1} = x_n - (x_n^2 - rate) / (2 * x_n)
		next := current - (current*current-rate)/(2.0*current)

		diff := next - current
		if diff < 0 {
			diff = -diff
		}

		if diff < 1e-8 {
			return next
		}
		current = next
	}
}

func calculateHandler(w http.ResponseWriter, r *http.Request) {
	rateStr := r.URL.Query().Get("rate")
	rate, err := strconv.ParseFloat(rateStr, 32)
	if err != nil {
		http.Error(w, "Invalid rate", http.StatusBadRequest)
		return
	}

	result := CalculateYield(float32(rate))
	fmt.Fprintf(w, "%f", result)
}

func main() {
	http.HandleFunc("/calculate", calculateHandler)
	http.ListenAndServe(":8080", nil)
}
EOF

    cd /home/user/pricing-engine
    go mod init pricing

    cat << 'EOF' > /home/user/pricing-engine/utils.go
package main

func init() {
	// Missing closing parenthesis to break build
	println("Initializing engine"
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
