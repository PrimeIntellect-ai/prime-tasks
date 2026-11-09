#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv golang sqlite3 ca-certificates
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/service/account
    mkdir -p /home/user/service/auth

    # Create schema.sql
    cat << 'EOF' > /home/user/schema.sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE,
    balance INTEGER DEFAULT 0,
    coupon_redeemed BOOLEAN DEFAULT 0
);
EOF

    # Initialize Go module
    cd /home/user/service
    go mod init example.com/service
    go get github.com/mattn/go-sqlite3

    # Create main.go
    cat << 'EOF' > /home/user/service/main.go
package main

import (
    "database/sql"
    "encoding/json"
    "fmt"
    "net/http"
    "example.com/service/account"
    "example.com/service/auth"
    _ "github.com/mattn/go-sqlite3"
)

func main() {
    db, err := sql.Open("sqlite3", "./db.sqlite3")
    if err != nil {
        panic(err)
    }
    defer db.Close()

    account.SetDB(db)
    auth.SetDB(db)

    http.HandleFunc("/register", func(w http.ResponseWriter, r *http.Request) {
        var req struct { Username string `json:"username"` }
        json.NewDecoder(r.Body).Decode(&req)
        account.CreateUser(req.Username)
        w.WriteHeader(http.StatusOK)
    })

    http.HandleFunc("/redeem", func(w http.ResponseWriter, r *http.Request) {
        var req struct {
            Username string `json:"username"`
            Code string `json:"code"`
        }
        json.NewDecoder(r.Body).Decode(&req)

        if req.Code == "WELCOME50" {
            success := account.RedeemCoupon(req.Username)
            if success {
                w.WriteHeader(http.StatusOK)
                return
            }
        }
        w.WriteHeader(http.StatusBadRequest)
    })

    http.HandleFunc("/balance", func(w http.ResponseWriter, r *http.Request) {
        username := r.URL.Query().Get("username")
        balance := account.GetBalance(username)
        fmt.Fprintf(w, "%d", balance)
    })

    http.ListenAndServe(":8080", nil)
}
EOF

    # Create account.go (Intentionally importing auth to create circular dependency)
    cat << 'EOF' > /home/user/service/account/account.go
package account

import (
    "database/sql"
    "time"
    "example.com/service/auth"
)

var DB *sql.DB

func SetDB(db *sql.DB) {
    DB = db
}

func CreateUser(username string) {
    DB.Exec("INSERT INTO users (username, balance, coupon_redeemed) VALUES (?, 0, 0)", username)
}

func RedeemCoupon(username string) bool {
    // Validate session via auth (causes circular import)
    if !auth.IsValid(username) {
        return false
    }

    var redeemed bool
    err := DB.QueryRow("SELECT coupon_redeemed FROM users WHERE username = ?", username).Scan(&redeemed)
    if err != nil || redeemed {
        return false
    }

    // Artificial delay to widen race condition window
    time.Sleep(50 * time.Millisecond)

    _, err = DB.Exec("UPDATE users SET balance = balance + 50, coupon_redeemed = 1 WHERE username = ?", username)
    return err == nil
}

func GetBalance(username string) int {
    var balance int
    DB.QueryRow("SELECT balance FROM users WHERE username = ?", username).Scan(&balance)
    return balance
}

func GetUserStatus(username string) string {
    return "active"
}
EOF

    # Create auth.go (Intentionally importing account to create circular dependency)
    cat << 'EOF' > /home/user/service/auth/auth.go
package auth

import (
    "database/sql"
    "example.com/service/account"
)

var DB *sql.DB

func SetDB(db *sql.DB) {
    DB = db
}

func IsValid(username string) bool {
    // Uses account package to check status (circular import)
    status := account.GetUserStatus(username)
    return status == "active"
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
