#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv nginx golang curl
    pip3 install pytest

    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/workspace/uploader.go
package main

import (
	"bytes"
	"fmt"
	"net/http"
	"sync"
)

func main() {
	var wg sync.WaitGroup
	results := make(chan string) // Unbuffered channel causes deadlock if not read continuously

	versions := []string{"1.0.1", "1.0.5", "1.0.12", "1.0.2"}

	for _, v := range versions {
		wg.Add(1)
		go func(version string) {
			defer wg.Done()
			jsonPayload := fmt.Sprintf(`{"platform":"android","branch":"release","version":"%s"}`, version)
			resp, err := http.Post("http://127.0.0.1:9090/add", "application/json", bytes.NewBuffer([]byte(jsonPayload)))
			if err == nil {
				resp.Body.Close()
				results <- "Success: " + version
			} else {
                results <- "Error: " + err.Error()
            }
		}(v)
	}

	// BUG: waiting before closing/reading channel deadlocks the goroutines trying to send
	wg.Wait()
	close(results)

	for r := range results {
		fmt.Println(r)
	}
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
