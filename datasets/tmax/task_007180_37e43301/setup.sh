#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import random
import numpy as np

random.seed(42)
np.random.seed(42)

n_users = 10000
users = []
sessions = []

# Generate deterministic data
for i in range(1, n_users + 1):
    group = 'A' if random.random() < 0.5 else 'B'
    # Group A: mean 50, std 15. Group B: mean 52, std 16
    mean = 50 if group == 'A' else 52
    std = 15 if group == 'A' else 16
    duration = max(0, np.random.normal(mean, std))

    # Introduce trailing spaces in users.csv to break naive joins
    user_id_users = f" {i} " if random.random() < 0.3 else str(i)
    user_id_sessions = str(i)

    users.append(f"{user_id_users},{group}\n")
    sessions.append(f"{user_id_sessions},{duration:.4f}\n")

with open('/home/user/users.csv', 'w') as f:
    f.write("user_id,group\n")
    f.writelines(users)

with open('/home/user/sessions.csv', 'w') as f:
    f.write("user_id,duration\n")
    f.writelines(sessions)

# Create the initial faulty Go script
go_code = """package main

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"strconv"
)

type Result struct {
	DiffMeans float64 `json:"diff_means"`
	CILower   float64 `json:"ci_lower"`
	CIUpper   float64 `json:"ci_upper"`
}

func main() {
    // Faulty logic that doesn't clean spaces
	usersFile, _ := os.Open("/home/user/users.csv")
	defer usersFile.Close()
	usersReader := csv.NewReader(usersFile)
	userRows, _ := usersReader.ReadAll()

	groupMap := make(map[string]string)
	for i, row := range userRows {
		if i == 0 { continue }
		groupMap[row[0]] = row[1]
	}

	sessionsFile, _ := os.Open("/home/user/sessions.csv")
	defer sessionsFile.Close()
	sessionsReader := csv.NewReader(sessionsFile)
	sessionRows, _ := sessionsReader.ReadAll()

	var sumA, sumB float64
	var countA, countB int
    var valsA, valsB []float64

	for i, row := range sessionRows {
		if i == 0 { continue }
		uid := row[0]
		dur, _ := strconv.ParseFloat(row[1], 64)

		if group, ok := groupMap[uid]; ok {
			if group == "A" {
				sumA += dur
				countA++
                valsA = append(valsA, dur)
			} else if group == "B" {
				sumB += dur
				countB++
                valsB = append(valsB, dur)
			}
		}
	}

    // This will produce NaN because countA and countB are heavily undercounted or 0 due to space mismatch,
    // actually it will just compute the wrong subset, but we'll let the user fix it.

    meanA := sumA / float64(countA)
    meanB := sumB / float64(countB)
    diff := meanB - meanA

    res := Result{DiffMeans: diff, CILower: 0, CIUpper: 0}
    out, _ := json.MarshalIndent(res, "", "  ")
    os.WriteFile("/home/user/results.json", out, 0644)
}
"""
with open('/home/user/analyze.go', 'w') as f:
    f.write(go_code)

os.chmod('/home/user/users.csv', 0o644)
os.chmod('/home/user/sessions.csv', 0o644)
os.chmod('/home/user/analyze.go', 0o644)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
