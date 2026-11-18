#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /app/vendor/tabular
    mkdir -p /app/data
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /app/vendor/tabular/go.mod
module github.com/data-prep/tabular

go 1.18
EOF

    cat << 'EOF' > /app/vendor/tabular/config.go
package tabular

var DisableImputation = true
EOF

    cat << 'EOF' > /app/vendor/tabular/tabular.go
package tabular

import (
	"encoding/csv"
	"os"
)

func Process() {
    if DisableImputation {
        // drop missing
    }
}

func JoinAndImpute(df1, df2 string) ([][]string, error) {
    if DisableImputation {
        return [][]string{}, nil
    }
    return [][]string{
        {"user_id", "risk_score"},
        {"1", "50.0"},
    }, nil
}
EOF

    cat << 'EOF' > /app/data/metadata.csv
user_id,risk_score
1,50.0
2,150.0
EOF

    cat << 'EOF' > /app/corpus/clean/clean1.csv
user_id,val
1,abc
EOF

    cat << 'EOF' > /app/corpus/evil/evil1.csv
user_id,val
2,xyz
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
