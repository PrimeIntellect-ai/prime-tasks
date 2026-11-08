#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go curl logrotate
    pip3 install pytest

    mkdir -p /home/user/proxy /home/user/backends /home/user/alerts
    touch /home/user/alerts/alerts.log
    chmod 777 /home/user/alerts/alerts.log

    cat << 'EOF' > /home/user/proxy/proxy.go
package main

import (
	"fmt"
	"io"
	"net/http"
	"net/http/httputil"
	"net/url"
	"time"
)

func checkBackends() {
	// The agent needs to modify this function to add retries and sleep
	urls := []string{"http://127.0.0.1:8081/ping", "http://127.0.0.1:8082/ping"}
	for _, u := range urls {
		resp, err := http.Get(u)
		if err != nil || resp.StatusCode != 200 {
			panic("Backend " + u + " is not available!")
		}
		resp.Body.Close()
	}
}

func main() {
	checkBackends()

	backend1, _ := url.Parse("http://127.0.0.1:8081")
	backend2, _ := url.Parse("http://127.0.0.1:8082")

	proxy1 := httputil.NewSingleHostReverseProxy(backend1)
	proxy2 := httputil.NewSingleHostReverseProxy(backend2)

	turn := 0
	http.HandleFunc("/alert", func(w http.ResponseWriter, r *http.Request) {
		if turn == 0 {
			turn = 1
			proxy1.ServeHTTP(w, r)
		} else {
			turn = 0
			proxy2.ServeHTTP(w, r)
		}
	})

	http.ListenAndServe(":8080", nil)
}
EOF

    cat << 'EOF' > /home/user/backends/backend.go
package main

import (
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
)

func main() {
	port := os.Args[1]
	http.HandleFunc("/ping", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
		w.Write([]byte("pong"))
	})
	http.HandleFunc("/alert", func(w http.ResponseWriter, r *http.Request) {
		body, _ := ioutil.ReadAll(r.Body)
		f, _ := os.OpenFile("/home/user/alerts/alerts.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		defer f.Close()
		f.WriteString(fmt.Sprintf("[%s] %s\n", port, string(body)))
		w.WriteHeader(200)
		w.Write([]byte("Alert logged"))
	})
	http.ListenAndServe(":"+port, nil)
}
EOF

    go build -o /home/user/backends/backend_bin /home/user/backends/backend.go

    cat << 'EOF' > /home/user/start_services.sh
#!/bin/bash
# Start proxy first, simulating systemd starting proxy before backend dependencies
/home/user/proxy/proxy_bin &
PROXY_PID=$!

sleep 3 # Artificial delay for backend startup

/home/user/backends/backend_bin 8081 &
/home/user/backends/backend_bin 8082 &

wait $PROXY_PID
EOF
    chmod +x /home/user/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
