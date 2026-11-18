#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang redis-server curl
    pip3 install pytest redis

    mkdir -p /app/ingest
    mkdir -p /app/aggregator

    cat << 'EOF' > /app/ingest/go.mod
module ingest

go 1.18

require github.com/buger/jsonparser v1.0.0
EOF

    cat << 'EOF' > /app/ingest/main.go
package main

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"io/ioutil"
	"net/http"

	"github.com/buger/jsonparser"
)

func main() {
	http.HandleFunc("/ingest", func(w http.ResponseWriter, r *http.Request) {
		body, _ := ioutil.ReadAll(r.Body)
		decoded, err := base64.StdEncoding.DecodeString(string(body))
		if err != nil {
			return
		}
		val, err := jsonparser.GetFloat(decoded, "val")
		if err != nil {
			return
		}
		http.Post(fmt.Sprintf("http://localhost:8082/add?val=%f", val), "application/json", bytes.NewBuffer([]byte{}))
	})
	http.ListenAndServe(":8081", nil)
}
EOF

    cat << 'EOF' > /app/aggregator/go.mod
module aggregator

go 1.18
EOF

    cat << 'EOF' > /app/aggregator/main.go
package main

import (
	"fmt"
	"net/http"
	"strconv"
)

var sum float32
var count int

func main() {
	http.HandleFunc("/add", func(w http.ResponseWriter, r *http.Request) {
		valStr := r.URL.Query().Get("val")
		val, _ := strconv.ParseFloat(valStr, 32)
		sum += float32(val)
		count++
	})
	http.HandleFunc("/avg", func(w http.ResponseWriter, r *http.Request) {
		if count == 0 {
			fmt.Fprintf(w, "0")
			return
		}
		fmt.Fprintf(w, "%f", float64(sum)/float64(count))
	})
	http.ListenAndServe(":8082", nil)
}
EOF

    cat << 'EOF' > /app/start.sh
#!/bin/bash
pkill -f ingest || true
pkill -f aggregator || true
cd /app/ingest && ./ingest &
cd /app/aggregator && ./aggregator &
sleep 2
EOF
    chmod +x /app/start.sh

    cat << 'EOF' > /app/test_harness.sh
#!/bin/bash
python3 -c '
import urllib.request, base64, json
for i in range(50000):
    val = 20.000000001
    payload = base64.b64encode(json.dumps({"val": val}).encode()).decode()
    req = urllib.request.Request("http://localhost:8081/ingest", data=payload.encode(), method="POST")
    try: urllib.request.urlopen(req)
    except: pass
'
curl -s http://localhost:8082/avg > /home/user/final_average.txt
EOF
    chmod +x /app/test_harness.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
