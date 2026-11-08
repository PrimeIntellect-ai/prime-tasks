#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang sqlite3
    pip3 install pytest

    mkdir -p /home/user/pipeline
    cd /home/user/pipeline

    sqlite3 data.db <<EOF
CREATE TABLE measurements (id INTEGER, f1 REAL, f2 REAL, is_train INTEGER);
INSERT INTO measurements VALUES (1, 10.0, 100.0, 1);
INSERT INTO measurements VALUES (2, 12.0, 110.0, 1);
INSERT INTO measurements VALUES (3, 14.0, 120.0, 1);
INSERT INTO measurements VALUES (4, 16.0, 130.0, 1);
INSERT INTO measurements VALUES (5, 20.0, 200.0, 0);
INSERT INTO measurements VALUES (6, 22.0, 210.0, 0);
EOF

    cat << 'EOF' > /home/user/pipeline/etl.go
package main

import (
	"database/sql"
	"fmt"
	"os"

	_ "github.com/mattn/go-sqlite3"
	"gonum.org/v1/gonum/stat"
)

type Row struct {
	ID      int
	F1      float64
	F2      float64
	IsTrain int
}

func main() {
	db, err := sql.Open("sqlite3", "data.db")
	if err != nil {
		panic(err)
	}
	defer db.Close()

	rows, err := db.Query("SELECT id, f1, f2, is_train FROM measurements ORDER BY id")
	if err != nil {
		panic(err)
	}
	defer rows.Close()

	var data []Row
	var f1All, f2All []float64

	for rows.Next() {
		var r Row
		rows.Scan(&r.ID, &r.F1, &r.F2, &r.IsTrain)
		data = append(data, r)

		// BUG: Appending all data, causing data leakage
		f1All = append(f1All, r.F1)
		f2All = append(f2All, r.F2)
	}

	f1Mean := stat.Mean(f1All, nil)
	f1Std := stat.StdDev(f1All, nil)

	f2Mean := stat.Mean(f2All, nil)
	f2Std := stat.StdDev(f2All, nil)

	trainFile, _ := os.Create("train_clean.csv")
	defer trainFile.Close()
	testFile, _ := os.Create("test_clean.csv")
	defer testFile.Close()

	trainFile.WriteString("id,f1,f2\n")
	testFile.WriteString("id,f1,f2\n")

	for _, r := range data {
		f1Scaled := (r.F1 - f1Mean) / f1Std
		f2Scaled := (r.F2 - f2Mean) / f2Std

		line := fmt.Sprintf("%d,%.4f,%.4f\n", r.ID, f1Scaled, f2Scaled)
		if r.IsTrain == 1 {
			trainFile.WriteString(line)
		} else {
			testFile.WriteString(line)
		}
	}
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
