#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go
pip3 install pytest

mkdir -p /app/healthd
mkdir -p /app/mock_target

# Create crash.dmp
dd if=/dev/urandom of=/app/crash.dmp bs=1024 count=1
echo -n "X-Malicious-Tag: len=128;payload=recursive_doom" >> /app/crash.dmp
dd if=/dev/urandom bs=1024 count=1 >> /app/crash.dmp

# Create parser.go
cat << 'EOF' > /app/healthd/parser.go
package main

// ParseTags reads tag data recursively
func ParseTags(input []byte) string {
	if len(input) == 0 {
		return ""
	}
	// BUG: casting to int8 causes overflow for values >= 128
	length := int8(input[0])

	if length <= 0 {
		// Infinite recursion triggered when length overflows to negative
		return ParseTags(input) 
	}

	if int(length) >= len(input) {
		return ""
	}

	return string(input[1:length+1]) + ParseTags(input[length+1:])
}
EOF

# Create healthd main.go
cat << 'EOF' > /app/healthd/main.go
package main

import (
	"fmt"
	"io"
	"net/http"
)

func checkHandler(w http.ResponseWriter, r *http.Request) {
	url := r.URL.Query().Get("url")
	resp, err := http.Get(url)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	tags := ParseTags(body)

	fmt.Fprintf(w, "status: healthy, tags: %s", tags)
}

func main() {
	http.HandleFunc("/check", checkHandler)
	http.ListenAndServe("127.0.0.1:8080", nil)
}
EOF

# Create mock_target main.go
cat << 'EOF' > /app/mock_target/main.go
package main

import (
	"net/http"
)

func main() {
	http.HandleFunc("/good", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte{0x04, 'o', 'k', 'a', 'y'})
	})
	http.HandleFunc("/bad", func(w http.ResponseWriter, r *http.Request) {
		// 0x80 is 128, which overflows int8 to -128
		w.Write([]byte{0x80, 'b', 'a', 'd'}) 
	})
	http.ListenAndServe("127.0.0.1:8081", nil)
}
EOF

# Create go.mod files
cd /app/healthd && go mod init healthd
cd /app/mock_target && go mod init mock_target

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
