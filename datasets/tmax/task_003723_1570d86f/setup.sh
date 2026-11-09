#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr golang imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/router.go
package main
import ("fmt"; "os"; "strings")
func main() {
    if len(os.Args) < 2 { return }
    f := os.Args[1]
    if strings.HasPrefix(f, "test_") { fmt.Print("/testing") } else
    if strings.HasSuffix(f, ".go") { fmt.Print("/gopath") } else
    if strings.Contains(f, "config") { fmt.Print("/settings") } else
    { fmt.Print("/unmatched") }
}
EOF

    cd /app
    go build -ldflags="-s -w" -o legacy_router router.go
    rm router.go

    # Generate the image with the routing rules
    convert -background white -fill black -font DejaVu-Sans -pointsize 24 label:"FILE ROUTING DIAGRAM\nRule 1: If filename starts with 'test_' -> /testing\nRule 2: If filename ends with '.go' -> /gopath\nRule 3: If filename contains 'config' -> /settings\nRule 4: Otherwise -> /unmatched\nNote: Rules are evaluated in order from 1 to 4." /app/routing_rules.png

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/bin /home/user/tester
    chmod -R 777 /home/user
