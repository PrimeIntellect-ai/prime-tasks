#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang sqlite3
    pip3 install pytest

    mkdir -p /home/user/app/logs
    cd /home/user/app
    go mod init recon

    # Create the SQLite DB
    sqlite3 data.db <<EOF
CREATE TABLE accounts (id INTEGER PRIMARY KEY, parent_id INTEGER);
CREATE TABLE transactions (id INTEGER PRIMARY KEY, account_id INTEGER, amount REAL, status TEXT);

-- Account hierarchy with a cycle
INSERT INTO accounts (id, parent_id) VALUES (1, NULL);
INSERT INTO accounts (id, parent_id) VALUES (2, 1);
INSERT INTO accounts (id, parent_id) VALUES (3, 2);
INSERT INTO accounts (id, parent_id) VALUES (4, 3);
-- The cycle: 5's parent is 4, but 4's parent is 5 (dirty data)
UPDATE accounts SET parent_id = 5 WHERE id = 4;
INSERT INTO accounts (id, parent_id) VALUES (5, 4);

-- Valid transactions (SETTLED)
INSERT INTO transactions (id, account_id, amount, status) VALUES (1, 1, 100.10, 'SETTLED');
INSERT INTO transactions (id, account_id, amount, status) VALUES (2, 2, 200.20, 'SETTLED');
INSERT INTO transactions (id, account_id, amount, status) VALUES (3, 3, 300.30, 'SETTLED');
INSERT INTO transactions (id, account_id, amount, status) VALUES (4, 4, 400.40, 'SETTLED');
INSERT INTO transactions (id, account_id, amount, status) VALUES (5, 5, 500.50, 'SETTLED');

-- Invalid transaction (PENDING)
INSERT INTO transactions (id, account_id, amount, status) VALUES (6, 1, 999.99, 'PENDING');
EOF

    # Create db.go
    cat << 'EOF' > db.go
package main

import (
	"database/sql"
	"log"

	_ "github.com/mattn/go-sqlite3"
)

func getDB() *sql.DB {
	db, err := sql.Open("sqlite3", "./data.db")
	if err != nil {
		log.Fatal(err)
	}
	return db
}

// BUG: Missing status = 'SETTLED' filter
func getTransactions(db *sql.DB, accountID int) []float32 {
	rows, err := db.Query("SELECT amount FROM transactions WHERE account_id = ?", accountID)
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()

	var amounts []float32
	for rows.Next() {
		var amount float32
		if err := rows.Scan(&amount); err != nil {
			log.Fatal(err)
		}
		amounts = append(amounts, amount)
	}
	return amounts
}

func getSubAccounts(db *sql.DB, parentID int) []int {
	rows, err := db.Query("SELECT id FROM accounts WHERE parent_id = ?", parentID)
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()

	var ids []int
	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err != nil {
			log.Fatal(err)
		}
		ids = append(ids, id)
	}
	return ids
}
EOF

    # Create aggregator.go
    cat << 'EOF' > aggregator.go
package main

import (
	"database/sql"
	"fmt"
)

// BUG: Uses float32 (precision loss) and lacks cycle detection (infinite recursion)
func calculateTotal(db *sql.DB, accountID int) float32 {
	var total float32

	// Add transactions for this account
	amounts := getTransactions(db, accountID)
	for _, amt := range amounts {
		total += amt
	}

	// Recurse into sub-accounts
	subAccounts := getSubAccounts(db, accountID)
	for _, subID := range subAccounts {
		total += calculateTotal(db, subID)
	}

	return total
}

func RunReconciliation() {
	db := getDB()
	defer db.Close()

	// Start at root account (id = 1)
	finalTotal := calculateTotal(db, 1)

	// Output formatted
	fmt.Printf("Total: %.2f\n", finalTotal)
}
EOF

    # Create main.go
    cat << 'EOF' > main.go
package main

func main() {
	RunReconciliation()
}
EOF

    # Create fake crash log
    cat << 'EOF' > logs/crash.log
goroutine 1 [running]:
main.calculateTotal(0xc0000a4000, 0x4)
        /home/user/app/aggregator.go:19 +0x145
main.calculateTotal(0xc0000a4000, 0x5)
        /home/user/app/aggregator.go:19 +0x145
main.calculateTotal(0xc0000a4000, 0x4)
        /home/user/app/aggregator.go:19 +0x145
... [repeated 100000 times]
fatal error: stack overflow
EOF

    go get github.com/mattn/go-sqlite3
    go mod tidy

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
