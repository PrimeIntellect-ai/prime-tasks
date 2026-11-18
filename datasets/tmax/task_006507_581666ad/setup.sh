#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git golang
    pip3 install pytest

    # Setup the finance-api repo
    mkdir -p /home/user/finance-api
    cd /home/user/finance-api
    git init
    git config user.name "Ops Engineer"
    git config user.email "ops@example.com"

    # Create module and good code
    cat << 'EOF' > go.mod
module finance

go 1.20
EOF

    cat << 'EOF' > yield.go
package finance

import "math"

func CalculateYield(principal float64, dailyRate float64, days int) float64 {
	return principal * math.Pow(1.0+dailyRate, float64(days))
}
EOF

    git add .
    git commit -m "Initial commit: implement CalculateYield"
    git tag v1.0.0

    # Add some dummy commits
    for i in {1..4}; do
        echo "// dummy comment $i" >> yield.go
        git commit -am "Refactor: clean up comments $i"
    done

    # Introduce the precision loss bug (Bad Commit)
    cat << 'EOF' > yield.go
package finance

import "math"

func CalculateYield(principal float64, dailyRate float64, days int) float64 {
	// Optimized for memory usage during bulk processing
	rate := float32(dailyRate)
	return principal * math.Pow(float64(1.0+rate), float64(days))
}
// dummy comment 4
EOF
    git commit -am "Optimize yield calculation memory footprint"

    # Save the expected bad commit hash for verification
    BAD_COMMIT=$(git rev-parse HEAD)
    echo $BAD_COMMIT > /home/user/.expected_bad_commit

    # Add more dummy commits to bury it
    for i in {5..9}; do
        echo "// dummy comment $i" >> yield.go
        git commit -am "Add more logging $i"
    done

    # Create the user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
