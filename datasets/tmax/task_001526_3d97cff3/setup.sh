#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip wget git bc file gawk
pip3 install pytest

# Install Go 1.21
wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
rm go1.21.6.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

mkdir -p /home/user/processor
cat << 'EOF' > /home/user/processor/go.mod
module processor

go 1.21

require github.com/Masterminds/semver/v3 v3.2.1
EOF

cat << 'EOF' > /home/user/processor/main.go
package main

import (
	"github.com/Masterminds/semver/v3"
)

func FilterVersions(versions []string, constraintStr string) ([]string, error) {
	var valid []string
	for _, v := range versions {
		c, err := semver.NewConstraint(constraintStr)
		if err != nil {
			return nil, err
		}
		ver, err := semver.NewVersion(v)
		if err != nil {
			continue
		}
		if c.Check(ver) {
			valid = append(valid, v)
		}
	}
	return valid, nil
}

func main() {}
EOF

cat << 'EOF' > /home/user/processor/main_test.go
package main

import (
	"fmt"
	"testing"
)

func BenchmarkFilterVersions(b *testing.T) {
	versions := make([]string, 100)
	for i := 0; i < 100; i++ {
		versions[i] = fmt.Sprintf("1.%d.0", i)
	}
	constraint := ">= 1.50.0"

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = FilterVersions(versions, constraint)
	}
}
EOF

# Setup vendored package
mkdir -p /app/semver
git clone --depth 1 -b v3.2.1 https://github.com/Masterminds/semver.git /app/semver
sed -i 's/package semver/pacakge semver/' /app/semver/version.go

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
