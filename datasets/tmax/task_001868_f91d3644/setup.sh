#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang
pip3 install pytest

mkdir -p /home/user/workspace

cat << 'EOF' > /home/user/workspace/input.csv
id,text,category_id
1,hello world,1
2,go is great,2
3,data science,
4,machine learning,3
5,missing values,
EOF

cat << 'EOF' > /home/user/workspace/pipeline.go
package main

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Record struct {
	ID         int
	Text       string
	CategoryID int
	Embedding  []float64
}

func ComputeEmbedding(text string) []float64 {
	// TODO: Implement mock embedding
	// [length, num_vowels, num_consonants]
	return []float64{0, 0, 0}
}

func Evaluate(records []Record) float64 {
	// TODO: Return average of the first embedding dimension
	return 0.0
}

func main() {
	file, err := os.Open("input.csv")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	reader := csv.NewReader(file)
	// Skip header
	_, _ = reader.Read()

	var records []Record
	lines, err := reader.ReadAll()
	if err != nil {
		panic(err)
	}

	for _, line := range lines {
		id, _ := strconv.Atoi(line[0])
		text := line[1]

		// BUG: skips row if empty instead of imputing 0
		catID, err := strconv.Atoi(line[2])
		if err != nil {
			continue 
		}

		emb := ComputeEmbedding(text)
		records = append(records, Record{
			ID:         id,
			Text:       text,
			CategoryID: catID,
			Embedding:  emb,
		})
	}

	score := Evaluate(records)

	// Write metrics
	metrics := map[string]interface{}{
		"total_rows_processed": len(records),
		"evaluation_score":     score,
	}

	out, _ := json.MarshalIndent(metrics, "", "  ")
	os.WriteFile("metrics.json", out, 0644)
	fmt.Println("Pipeline finished.")
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
