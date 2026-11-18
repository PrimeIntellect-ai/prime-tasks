#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go iptables gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/audit /home/user/services

    cat <<'EOF' > /home/user/audit/firewall_bypass.go
package main

import (
	"crypto/sha256"
	"fmt"
	"net/http"
)

// Backdoor configuration
const secretHash = "19f0322ba5bc217822a901869e961917f8b5fbb204f14d86b978385202872bc0" // SHA256 of "4829"
const backdoorPort = "13337"

func main() {
	fmt.Printf("Listening on %s...\n", backdoorPort)
	// Implementation omitted
}
EOF

    echo "alpha_clean_code" > /home/user/services/service_alpha
    echo "gamma_clean_code" > /home/user/services/service_gamma
    echo "beta_malicious_code" > /home/user/services/service_beta

    ALPHA_HASH=$(sha256sum /home/user/services/service_alpha | awk '{print $1}')
    GAMMA_HASH=$(sha256sum /home/user/services/service_gamma | awk '{print $1}')
    BETA_FAKE_HASH=$(echo "beta_clean_code" | sha256sum | awk '{print $1}')

    cat <<EOF > /home/user/audit/checksums.txt
$ALPHA_HASH  service_alpha
$BETA_FAKE_HASH  service_beta
$GAMMA_HASH  service_gamma
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
