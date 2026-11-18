#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server golang curl
    pip3 install pytest flask redis requests

    mkdir -p /home/user/app/aggregator
    mkdir -p /home/user/app/integrator

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
python3 /home/user/app/aggregator/app.py &
cd /home/user/app/integrator && ./integrator &
EOF
    chmod +x /home/user/app/start_services.sh

    cat << 'EOF' > /home/user/app/integrator/solver.go
package main

import "math"

// Returns next state, dt, and error
func adaptStep(dt float64, err float64, tol float64) float64 {
    // BUGGY ADAPTATION: causes divergence to 0
    // The agent must fix this to clamp at 1e-6 and scale properly
    // e.g., new_dt := dt * math.Pow(tol/err, 0.2)
    // if new_dt < 1e-6 { new_dt = 1e-6 }
    new_dt := dt - (err * 1000.0) 
    return new_dt
}
EOF

    cat << 'EOF' > /home/user/app/integrator/main.go
package main

import (
	"fmt"
	"net/http"
)

func ProcessNetworks() {
	// TODO: process the equations using a WaitGroup and goroutines
	fmt.Println("Processing networks...")
}

func solveHandler(w http.ResponseWriter, r *http.Request) {
	// TODO: Add authorization check for Bearer ds-model-fit-token
	ProcessNetworks()
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("Solved"))
}

func main() {
	http.HandleFunc("/solve", solveHandler)
	http.ListenAndServe(":8080", nil)
}
EOF

    cat << 'EOF' > /home/user/app/aggregator/app.py
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/results', methods=['GET'])
def get_results():
    return jsonify([])

if __name__ == '__main__':
    app.run(port=5000)
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
