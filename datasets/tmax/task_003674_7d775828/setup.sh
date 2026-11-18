#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go curl jq
    pip3 install pytest

    mkdir -p /home/user/api-version-resolver

    cat << 'EOF' > /home/user/api-version-resolver/current.json
{
  "alpha-lib": "1.2.3",
  "beta-core": "2.10.1",
  "gamma-utils": "0.5.9",
  "delta-sys": "3.0.0",
  "epsilon-net": "1.15.2"
}
EOF

    cat << 'EOF' > /home/user/api-version-resolver/wanted.json
{
  "alpha-lib": "1.10.0",
  "beta-core": "2.9.5",
  "gamma-utils": "0.6.0",
  "delta-sys": "3.0.0",
  "epsilon-net": "1.2.9"
}
EOF

    cat << 'EOF' > /home/user/api-version-resolver/main.go
package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"sort"
	"strings"
	// "strconv" // Bug: missing import for compilation, missing semver parse logic
)

type Update struct {
	Package string `json:"package"`
	From    string `json:"from"`
	To      string `json:"to"`
}

func loadJSON(filename string) (map[string]string, error) {
	b, err := os.ReadFile(filename)
	if err != nil {
		return nil, err
	}
	var data map[string]string
	err = json.Unmarshal(b, &data)
	return data, err
}

// BUG: naive string comparison instead of actual SemVer
func isGreater(wanted, current string) bool {
	return wanted > current 
}

func updatesHandler(w http.ResponseWriter, r *http.Request) {
	current, _ := loadJSON("current.json")
	wanted, _ := loadJSON("wanted.json")

	var updates []Update
	for pkg, currVer := range current {
		wantVer, ok := wanted[pkg]
		if ok && isGreater(wantVer, currVer) {
			updates = append(updates, Update{
				Package: pkg,
				From:    currVer,
				To:      wantVer,
			})
		}
	}

	// BUG: Does not sort the slice alphabetically

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(updates)
}

func main() {
	http.HandleFunc("/updates", updatesHandler)
	// BUG: port missing colon
	http.ListenAndServe("8080", nil) 
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
