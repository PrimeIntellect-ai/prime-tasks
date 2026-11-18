#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git golang-go espeak
    pip3 install pytest

    # Create audio file
    mkdir -p /app
    espeak -w /app/voicemail.wav "The server authorization PIN code is eight four two nine five."

    # Create user
    useradd -m -s /bin/bash user || true

    # Create git repository
    mkdir -p /home/user/math_server
    cd /home/user/math_server
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    # Commit 1
    cat << 'EOF' > main.go
package main
import ("encoding/json";"fmt";"net/http")
type Request struct { Number int `json:"number"` }
type Response struct { Factors []int `json:"factors"` }
func primeFactors(n int) []int {
	factors := []int{}
	for i := 2; i*i <= n; i++ {
		for n%i == 0 { factors = append(factors, i); n /= i }
	}
	if n > 1 { factors = append(factors, n) }
	return factors
}
func handler(w http.ResponseWriter, r *http.Request) {
	var req Request
	json.NewDecoder(r.Body).Decode(&req)
	json.NewEncoder(w).Encode(Response{Factors: primeFactors(req.Number)})
}
func main() {
	http.HandleFunc("/prime_factors", handler)
	fmt.Println("Starting server on :9000")
	http.ListenAndServe(":9000", nil)
}
EOF
    git add main.go
    git commit -m "Initial commit"
    git tag v1.0.0

    # Commits 2 to 149
    for i in $(seq 2 149); do
        echo "// comment $i" >> main.go
        git commit -am "Commit $i"
    done

    # Commit 150 (Introduce data race)
    cat << 'EOF' > main.go
package main
import ("encoding/json";"fmt";"net/http")
type Request struct { Number int `json:"number"` }
type Response struct { Factors []int `json:"factors"` }
var factors []int
func primeFactors(n int) []int {
	factors = []int{}
	for i := 2; i*i <= n; i++ {
		for n%i == 0 { factors = append(factors, i); n /= i }
	}
	if n > 1 { factors = append(factors, n) }
	return factors
}
func handler(w http.ResponseWriter, r *http.Request) {
	var req Request
	json.NewDecoder(r.Body).Decode(&req)
	json.NewEncoder(w).Encode(Response{Factors: primeFactors(req.Number)})
}
func main() {
	http.HandleFunc("/prime_factors", handler)
	fmt.Println("Starting server on :9000")
	http.ListenAndServe(":9000", nil)
}
EOF
    git commit -am "Commit 150"

    # Commits 151 to 199
    for i in $(seq 151 199); do
        echo "// comment $i" >> main.go
        git commit -am "Commit $i"
    done

    # Commit 200 (Introduce syntax error)
    sed -i 's/fmt.Println/fmt.Printlnf/' main.go
    git commit -am "Commit 200"

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /app
