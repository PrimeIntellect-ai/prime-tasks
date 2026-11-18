#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang espeak sqlite3
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Generate terms.csv with 100 random pairs
    for i in {1..100}; do
        echo "source$i,target$i" >> /home/user/terms.csv
    done
    # Add some real words to make it interesting
    cat << 'EOF' >> /home/user/terms.csv
cat,gato
dog,perro
apple,manzana
house,casa
EOF

    # Generate audio file
    espeak -w /app/instructions.wav "pineapple"

    # Create oracle process in Go
    cat << 'EOF' > /app/oracle.go
package main

import (
	"bufio"
	"encoding/csv"
	"fmt"
	"io"
	"os"
	"regexp"
	"strings"

	"golang.org/x/text/unicode/norm"
)

func main() {
	f, err := os.Open("/home/user/terms.csv")
	if err != nil {
		panic(err)
	}
	defer f.Close()
	r := csv.NewReader(f)
	records, _ := r.ReadAll()
	dict := make(map[string]string)
	for _, rec := range records {
		if len(rec) == 2 {
			dict[rec[0]] = rec[1]
		}
	}

	reader := bufio.NewReader(os.Stdin)
	re := regexp.MustCompile(`[A-Za-z]+|[^A-Za-z]+`)

	for {
		line, err := reader.ReadString('\n')
		if err != nil && err != io.EOF {
			break
		}

		normalized := norm.NFC.String(line)

		tokens := re.FindAllString(normalized, -1)
		var out strings.Builder
		for _, token := range tokens {
			if matched, _ := regexp.MatchString(`^[A-Za-z]+$`, token); matched {
				if token == "SECRET" {
					out.WriteString("pineapple")
				} else if val, ok := dict[token]; ok {
					out.WriteString(val)
				} else {
					out.WriteString(token)
				}
			} else {
				out.WriteString(token)
			}
		}
		fmt.Print(out.String())

		if err == io.EOF {
			break
		}
	}
}
EOF

    cd /app
    go mod init oracle
    go get golang.org/x/text/unicode/norm
    go build -o oracle_process oracle.go
    rm oracle.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
