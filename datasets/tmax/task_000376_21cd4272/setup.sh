#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip wget tar coreutils
pip3 install pytest

# Install Go 1.20
wget https://go.dev/dl/go1.20.14.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.20.14.linux-amd64.tar.gz
ln -s /usr/local/go/bin/go /usr/bin/go
ln -s /usr/local/go/bin/gofmt /usr/bin/gofmt
rm go1.20.14.linux-amd64.tar.gz

useradd -m -s /bin/bash user || true

mkdir -p /home/user/pipeline
cat << 'EOF' > /home/user/pipeline/deps.json
{
  "auth-service": ["db-lib", "logger"],
  "db-lib": ["logger"],
  "logger": [],
  "mathservice/algebra": ["mathservice/geometry", "logger"],
  "mathservice/geometry": ["mathservice/algebra"],
  "payment-service": ["auth-service", "mathservice/algebra"]
}
EOF

mkdir -p /home/user/service/algebra
mkdir -p /home/user/service/geometry

cat << 'EOF' > /home/user/service/go.mod
module mathservice

go 1.20
EOF

cat << 'EOF' > /home/user/service/algebra/algebra.go
package algebra

import "mathservice/geometry"

type Vector struct {
	X, Y float64
}

func Solve(p geometry.Point) Vector {
	return Vector{X: p.X, Y: p.Y}
}
EOF

cat << 'EOF' > /home/user/service/geometry/geometry.go
package geometry

import "mathservice/algebra"

type Point struct {
	X, Y float64
}

func Distance(v algebra.Vector) float64 {
	return v.X*v.X + v.Y*v.Y
}
EOF

chmod -R 777 /home/user
