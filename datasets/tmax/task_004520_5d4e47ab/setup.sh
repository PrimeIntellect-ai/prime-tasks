#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/users.csv
user_id,name
U1,Alice
U2,Bob
U3,Charlie
U4,Dave
EOF

    cat << 'EOF' > /home/user/transactions.csv
tx_id,user_id,amount,date
T1,U1,100.50,2023-01-01
T2,U1,50.25,2023-01-02
T3,U2,200.00,2023-01-01
T4,U1,10.00,2023-01-03
T5,U3,5.00,2023-01-01
T6,U2,300.00,2023-01-04
EOF

    cat << 'EOF' > /home/user/process.go
package main

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"sort"
	"strconv"
)

type User struct {
	UserID         string  `json:"user_id"`
	Name           string  `json:"name"`
	TotalSpent     float64 `json:"total_spent"`
	MaxTransaction float64 `json:"max_transaction"`
}

type Transaction struct {
	TxID   string
	UserID string
	Amount float64
}

func main() {
	usersFile, _ := os.Open("/home/user/users.csv")
	defer usersFile.Close()
	usersData, _ := csv.NewReader(usersFile).ReadAll()

	txFile, _ := os.Open("/home/user/transactions.csv")
	defer txFile.Close()
	txData, _ := csv.NewReader(txFile).ReadAll()

	var transactions []Transaction
	for i, row := range txData {
		if i == 0 {
			continue // skip header
		}
		amount, _ := strconv.ParseFloat(row[2], 64)
		transactions = append(transactions, Transaction{
			TxID:   row[0],
			UserID: row[1],
			Amount: amount,
		})
	}

	var users []User
	for i, row := range usersData {
		if i == 0 {
			continue
		}
		u := User{
			UserID: row[0],
			Name:   row[1],
		}

		// BUG: Implicit cross join. Fails to check u.UserID == tx.UserID
		for _, tx := range transactions {
			u.TotalSpent += tx.Amount
			// BUG: Max transaction logic missing
		}
		users = append(users, u)
	}

	sort.Slice(users, func(i, j int) bool {
		return users[i].UserID < users[j].UserID
	})

	outFile, _ := os.Create("/home/user/output.json")
	defer outFile.Close()
	encoder := json.NewEncoder(outFile)
	encoder.SetIndent("", "  ")
	encoder.Encode(users)
}
EOF

    chmod -R 777 /home/user
