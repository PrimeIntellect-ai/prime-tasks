#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server wget curl
    pip3 install pytest

    # Install newer Go version to support go-redis/v9
    wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
    rm go1.21.6.linux-amd64.tar.gz
    ln -s /usr/local/go/bin/go /usr/bin/go

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/collector
    mkdir -p /home/user/app/api

    cat << 'EOF' > /home/user/app/config.env
REDIS_HOST=
REDIS_PORT=
API_TOKEN=
EOF

    cat << 'EOF' > /home/user/app/start.sh
#!/bin/bash
set -a
source /home/user/app/config.env
set +a

redis-server --daemonize yes
sleep 1

cd /home/user/app/collector && go run main.go &
cd /home/user/app/api && go run main.go &
wait
EOF
    chmod +x /home/user/app/start.sh

    cat << 'EOF' > /home/user/app/collector/main.go
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/redis/go-redis/v9"
)

var (
	rdb *redis.Client
	ctx = context.Background()
	// BUG: No mutex, race condition
	averages = make(map[string]float64)
)

type SensorData struct {
	SensorID string  `json:"sensor_id"`
	Value    float64 `json:"value"`
}

func ingestHandler(w http.ResponseWriter, r *http.Request) {
	var data SensorData
	err := json.NewDecoder(r.Body).Decode(&data)
	if err != nil {
		// BUG: panics on bad JSON
		panic(err)
	}

	current, exists := averages[data.SensorID]
	if !exists {
		averages[data.SensorID] = data.Value
	} else {
		averages[data.SensorID] = current*0.9 + data.Value*0.1
	}

	err = rdb.Set(ctx, data.SensorID, averages[data.SensorID], 0).Err()
	if err != nil {
		http.Error(w, "Redis error", 500)
		return
	}

	w.WriteHeader(http.StatusOK)
}

func main() {
	redisHost := os.Getenv("REDIS_HOST")
	redisPort := os.Getenv("REDIS_PORT")
	rdb = redis.NewClient(&redis.Options{
		Addr: fmt.Sprintf("%s:%s", redisHost, redisPort),
	})

	http.HandleFunc("/ingest", ingestHandler)
	log.Fatal(http.ListenAndServe(":8081", nil))
}
EOF

    cat << 'EOF' > /home/user/app/api/main.go
package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"

	"github.com/redis/go-redis/v9"
)

var (
	rdb *redis.Client
	ctx = context.Background()
)

func sensorHandler(w http.ResponseWriter, r *http.Request) {
	token := os.Getenv("API_TOKEN")
	authHeader := r.Header.Get("Authorization")
	if authHeader != "Bearer "+token {
		http.Error(w, "Unauthorized", 401)
		return
	}

	parts := strings.Split(r.URL.Path, "/")
	if len(parts) < 3 {
		http.Error(w, "Not found", 404)
		return
	}
	sensorID := parts[2]

	val, err := rdb.Get(ctx, sensorID).Result()
	if err != nil {
		http.Error(w, "Not found", 404)
		return
	}

	fmt.Fprint(w, val)
}

func main() {
	redisHost := os.Getenv("REDIS_HOST")
	redisPort := os.Getenv("REDIS_PORT")
	rdb = redis.NewClient(&redis.Options{
		Addr: fmt.Sprintf("%s:%s", redisHost, redisPort),
	})

	http.HandleFunc("/sensors/", sensorHandler)
	log.Fatal(http.ListenAndServe(":8082", nil))
}
EOF

    cd /home/user/app/collector
    go mod init collector
    go get github.com/redis/go-redis/v9

    cd /home/user/app/api
    go mod init api
    go get github.com/redis/go-redis/v9

    chmod -R 777 /home/user
