#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /app/dataset-catalog/scorer

    cat << 'EOF' > /app/dataset-catalog/go.mod
module dataset-catalog

go 1.18
EOF

    cat << 'EOF' > /app/dataset-catalog/main.go
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"

	"dataset-catalog/scorer"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	http.HandleFunc("/score", func(w http.ResponseWriter, r *http.Request) {
		priorStr := r.URL.Query().Get("prior")
		likelihoodStr := r.URL.Query().Get("likelihood")
		marginalStr := r.URL.Query().Get("marginal")

		prior, _ := strconv.ParseFloat(priorStr, 64)
		likelihood, _ := strconv.ParseFloat(likelihoodStr, 64)
		marginal, _ := strconv.ParseFloat(marginalStr, 64)

		posterior := scorer.CalculatePosterior(prior, likelihood, marginal)

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]float64{"posterior": posterior})
	})

	addr := fmt.Sprintf("127.0.0.1:%s", port)
	log.Printf("Listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}
EOF

    cat << 'EOF' > /app/dataset-catalog/scorer/bayes.go
package scorer

func CalculatePosterior(prior, likelihood, marginal float64) float64 {
    // Deliberate perturbation: using addition instead of multiplication
    return (prior + likelihood) / marginal
}
EOF

    cat << 'EOF' > /app/dataset-catalog/scorer/bayes_test.go
package scorer

import (
	"testing"
)

func TestCalculatePosterior(t *testing.T) {
	prior := 0.4
	likelihood := 0.8
	marginal := 0.5
	expected := 0.64

	result := CalculatePosterior(prior, likelihood, marginal)
	if result != expected {
		t.Errorf("Expected %f, got %f", expected, result)
	}
}

func BenchmarkCalculatePosterior(b *testing.B) {
	for i := 0; i < b.N; i++ {
		CalculatePosterior(0.4, 0.8, 0.5)
	}
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
