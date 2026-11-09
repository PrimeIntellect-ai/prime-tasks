#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/service

    cat << 'EOF' > /home/user/service/main.go
package main

import (
	"fmt"
	"net/http"
	"runtime"
	"time"
)

func processHandler(w http.ResponseWriter, r *http.Request) {
	resultChan := make(chan string)

	go func() {
		// Simulate a long-running external API call or DB query
		time.Sleep(1 * time.Second)
		resultChan <- "Success"
	}()

	select {
	case res := <-resultChan:
		w.Write([]byte(res))
	case <-r.Context().Done():
		// Handle client cancellation
		return
	}
}

func statsHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintf(w, "%d", runtime.NumGoroutine())
}

func main() {
	http.HandleFunc("/process", processHandler)
	http.HandleFunc("/stats", statsHandler)
	http.ListenAndServe(":8080", nil)
}
EOF

    cat << 'EOF' > /home/user/client.py
import threading
import urllib.request

def fetch():
    try:
        # Timeout quickly to trigger client cancellation in Go
        urllib.request.urlopen('http://localhost:8080/process', timeout=0.2)
    except Exception:
        pass

threads = []
for _ in range(50):
    t = threading.Thread(target=fetch)
    t.start()
    threads.append(t)

for t in threads:
    t.join()
EOF

    cat << 'EOF' > /home/user/verify.sh
#!/bin/bash
# wait for server to be up
sleep 1

# get initial goroutines
START=$(curl -s http://localhost:8080/stats)
if [ -z "$START" ]; then
    echo "FAILURE: Could not reach /stats" > /home/user/leak_fixed.log
    exit 1
fi

# run python script
python3 /home/user/client.py

# wait for simulated work to finish to see if goroutines were leaked
sleep 2

# get final goroutines
END=$(curl -s http://localhost:8080/stats)

DIFF=$((END - START))

if [ $DIFF -lt 5 ]; then
    echo "SUCCESS: Goroutine difference is $DIFF" > /home/user/leak_fixed.log
else
    echo "FAILURE: Goroutine difference is $DIFF" > /home/user/leak_fixed.log
fi
EOF

    chmod +x /home/user/verify.sh
    cd /home/user/service && go mod init service

    chmod -R 777 /home/user
