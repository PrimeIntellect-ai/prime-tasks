#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/dataset

    cat << 'EOF' > /home/user/dataset/messages.csv
ham,hello friend how are you
ham,i am doing well today
spam,buy cheap watches now
ham,let us meet for lunch
ham,the weather is nice
spam,win a free gift card
ham,call me back when you can
ham,see you tomorrow morning
spam,urgent your account is locked
ham,this is a completely unique test message
EOF

    cat << 'EOF' > /home/user/prepare_data.go
package main

import (
	"encoding/csv"
	"fmt"
	"os"
	"strings"
)

func Tokenize(text string, vocab map[string]int) []int {
	words := strings.Fields(text)
	var tokens []int
	for _, w := range words {
		if id, ok := vocab[w]; ok {
			tokens = append(tokens, id)
		} else {
			tokens = append(tokens, 0) // UNK
		}
	}
	return tokens
}

func main() {
	f, err := os.Open("dataset/messages.csv")
	if err != nil {
		panic(err)
	}
	defer f.Close()

	reader := csv.NewReader(f)
	records, _ := reader.ReadAll()

	vocab := make(map[string]int)
	vocabID := 1 // 0 is reserved for UNK

	// BUG: Building vocab on ALL data
	for _, record := range records {
		words := strings.Fields(record[1])
		for _, w := range words {
			if _, exists := vocab[w]; !exists {
				vocab[w] = vocabID
				vocabID++
			}
		}
	}

	trainSize := int(0.8 * float64(len(records)))
	_ = trainSize // Used for split later

	// ... missing logic to output test_features.csv
}
EOF

    cd /home/user
    go mod init prepare_data

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
