#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gdb
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the legacy binary source
    cat << 'EOF' > /tmp/legacy.go
package main
import "fmt"
var Seed float64 = 0.54321
func main() {
    // Deliberately not printing the seed to force debugger usage
    fmt.Println("Legacy simulation finished.")
}
EOF

    # Compile the legacy binary (unstripped so gdb can read main.Seed)
    go build -o /home/user/old_sim /tmp/legacy.go
    rm /tmp/legacy.go

    # Create the broken simulator.go
    cat << 'EOF' > /home/user/simulator.go
package main

import "fmt"

// Missing implementation to trigger linker error
func getSeed() float64

func main() {
	var x float32 = float32(getSeed())
	var r float32 = 3.95

	for i := 0; i < 10000; i++ {
		x = r * x * (1.0 - x)
	}

	fmt.Printf("%.6f\n", x)
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
