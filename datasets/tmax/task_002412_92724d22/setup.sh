#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server golang curl
    pip3 install pytest requests

    mkdir -p /app/nginx /app/worker /app/corpus/evil /app/corpus/clean

    # Create start.sh
    cat << 'EOF' > /app/start.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /app/nginx/nginx.conf
cd /app/worker
go run main.go analyzer.go -port 8081 &
go run main.go analyzer.go -port 8082 &
go run main.go analyzer.go -port 8083 &
wait
EOF
    chmod +x /app/start.sh

    # Create nginx.conf
    cat << 'EOF' > /app/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            # TODO: Configure load balancing
        }
    }
}
EOF

    # Create go.mod
    cat << 'EOF' > /app/worker/go.mod
module worker

go 1.18
EOF

    # Create main.go
    cat << 'EOF' > /app/worker/main.go
package main

import (
    "encoding/json"
    "fmt"
    "net/http"
    "os"
)

type Request struct {
    Sequence string `json:"sequence"`
}

type Response struct {
    Status string `json:"status"`
}

func analyzeHandler(w http.ResponseWriter, r *http.Request) {
    // TODO: Connect to Redis, cache results, handle concurrently
    var req Request
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    status := AnalyzeSequence(req.Sequence)

    res := Response{Status: status}
    json.NewEncoder(w).Encode(res)
}

func main() {
    port := "8081"
    if len(os.Args) > 2 && os.Args[1] == "-port" {
        port = os.Args[2]
    }
    http.HandleFunc("/analyze", analyzeHandler)
    fmt.Printf("Worker listening on port %s\n", port)
    http.ListenAndServe(":"+port, nil)
}
EOF

    # Create analyzer.go
    cat << 'EOF' > /app/worker/analyzer.go
package main

func AnalyzeSequence(seq string) string {
    // TODO: Implement sequence analysis and filtering logic
    return "clean"
}
EOF

    # Generate corpus
    python3 -c "
import os
import random

os.makedirs('/app/corpus/evil', exist_ok=True)
os.makedirs('/app/corpus/clean', exist_ok=True)

random.seed(42)

for i in range(20):
    seq = ''.join(random.choices(['A', 'C', 'G', 'T'], k=200))
    with open(f'/app/corpus/clean/seq_{i}.txt', 'w') as f:
        f.write(seq)

for i in range(20):
    seq = []
    for j in range(200):
        gc_prob = 0.2 + (0.7 * (j / 199))
        if random.random() < gc_prob:
            seq.append(random.choice(['G', 'C']))
        else:
            seq.append(random.choice(['A', 'T']))
    with open(f'/app/corpus/evil/seq_{i}.txt', 'w') as f:
        f.write(''.join(seq))
"

    # Initialize go mod
    cd /app/worker
    go mod tidy

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
