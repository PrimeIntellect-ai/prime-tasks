#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git sqlite3 golang
    pip3 install pytest

    mkdir -p /home/user/reconciler
    mkdir -p /home/user/data

    cd /home/user/reconciler

    git init
    git config user.name "DevOps"
    git config user.email "devops@example.com"

    # Create sqlite DB
    sqlite3 /home/user/data/config.db <<EOF
CREATE TABLE config (id INTEGER PRIMARY KEY, key TEXT, val TEXT, active INTEGER);
INSERT INTO config (key, val, active) VALUES ('worker_threads', '4', 1);
INSERT INTO config (key, val, active) VALUES ('debug_mode', 'true', 1);
INSERT INTO config (key, val, active) VALUES ('old_setting', 'obsolete', 0);
EOF

    # Initial code with secret
    cat << 'EOF' > main.go
package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"sync"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

func main() {
	secret := os.Getenv("SECRET_TOKEN")
	if secret == "" {
		secret = "super_secret_devops_token_99" // HARDCODED
	}
	if secret != "super_secret_devops_token_99" {
		log.Fatal("Unauthorized")
	}

	db, err := sql.Open("sqlite3", "/home/user/data/config.db")
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	for attempt := 1; attempt <= 10; attempt++ {
		// BUG: Fetching all, including inactive
		rows, err := db.Query("SELECT key, val FROM config")
		if err != nil {
			log.Fatal(err)
		}

		state := make(map[string]string)
		var wg sync.WaitGroup

		for rows.Next() {
			var k, v string
			if err := rows.Scan(&k, &v); err != nil {
				log.Fatal(err)
			}
			wg.Add(1)
			go func(key, val string) {
				defer wg.Done()
				// BUG: concurrent map write
				state[key] = val
			}(k, v)
		}
		wg.Wait()
		rows.Close()

		// Convergence check
		converged := true
		for k := range state {
			// BUG: incorrect convergence logic always sets to false because of len check mismatch
			if len(state) > 0 {
			    converged = false
			}
		}

		if converged {
			fmt.Println("State converged successfully")
			data, _ := json.Marshal(state)
			os.WriteFile("/home/user/converged_state.json", data, 0644)
			return
		}
		fmt.Printf("Attempt %d failed to converge...\n", attempt)
		time.Sleep(100 * time.Millisecond)
	}
	log.Fatal("Failed to converge after 10 attempts")
}
EOF

    # Initialize go module
    go mod init reconciler
    go get github.com/mattn/go-sqlite3
    go mod tidy

    git add .
    git commit -m "Initial commit with state reconciler"

    # Remove secret
    cat << 'EOF' > main.go
package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"sync"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

func main() {
	secret := os.Getenv("SECRET_TOKEN")
	if secret != "super_secret_devops_token_99" {
		log.Fatal("Unauthorized")
	}

	db, err := sql.Open("sqlite3", "/home/user/data/config.db")
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	for attempt := 1; attempt <= 10; attempt++ {
		// BUG: Fetching all, including inactive
		rows, err := db.Query("SELECT key, val FROM config")
		if err != nil {
			log.Fatal(err)
		}

		state := make(map[string]string)
		var wg sync.WaitGroup

		for rows.Next() {
			var k, v string
			if err := rows.Scan(&k, &v); err != nil {
				log.Fatal(err)
			}
			wg.Add(1)
			go func(key, val string) {
				defer wg.Done()
				// BUG: concurrent map write
				state[key] = val
			}(k, v)
		}
		wg.Wait()
		rows.Close()

		// Convergence check
		converged := true
		for k := range state {
			// BUG: incorrect convergence logic always sets to false
			if len(state) > 0 {
			    converged = false
			}
		}

		if converged {
			fmt.Println("State converged successfully")
			data, _ := json.Marshal(state)
			os.WriteFile("/home/user/converged_state.json", data, 0644)
			return
		}
		fmt.Printf("Attempt %d failed to converge...\n", attempt)
		time.Sleep(100 * time.Millisecond)
	}
	log.Fatal("Failed to converge after 10 attempts")
}
EOF

    git add main.go
    git commit -m "Remove hardcoded secret token"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
