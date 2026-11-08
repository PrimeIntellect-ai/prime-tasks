#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang
pip3 install pytest

mkdir -p /home/user/ingester/parser /home/user/ingester/processor /home/user/data

cat << 'EOF' > /home/user/ingester/go.mod
module log-ingester

go 1.18
EOF

cat << 'EOF' > /home/user/ingester/parser/parser.go
package parser

import (
	"strings"
)

type Record struct {
	Timestamp string `json:"timestamp"`
	IP        string `json:"ip"`
	UserAgent string `json:"user_agent"`
}

// ParseLine parses key=value pairs. Values can be quoted.
func ParseLine(line string) Record {
	rec := Record{}
	i := 0
	n := len(line)

	for i < n {
		// skip spaces
		for i < n && line[i] == ' ' {
			i++
		}
		if i == n {
			break
		}

		// find key
		eqIdx := strings.IndexByte(line[i:], '=')
		if eqIdx == -1 {
			break // malformed
		}
		key := line[i : i+eqIdx]
		i += eqIdx + 1

		var val string
		if i < n && line[i] == '"' {
			// BUG: If there is an escaped quote \" inside, this simple IndexByte finds the wrong quote!
			// And if the string ends in \", it might panic or slice incorrectly.
			// Specifically, the bug panics if there is a trailing slash before a quote, or if index calculations go out of bounds.
			i++ // skip opening quote
			endIdx := strings.IndexByte(line[i:], '"')

			// DELIBERATE BUG: Not handling escaped quotes properly, leading to out of bounds if endIdx is the last character and we do i+endIdx+1
			val = line[i : i+endIdx]
			i += endIdx + 1
		} else {
			spIdx := strings.IndexByte(line[i:], ' ')
			if spIdx == -1 {
				val = line[i:]
				i = n
			} else {
				val = line[i : i+spIdx]
				i += spIdx + 1
			}
		}

		switch key {
		case "ts":
			rec.Timestamp = val
		case "ip":
			rec.IP = val
		case "ua":
			rec.UserAgent = val
		}
	}
	return rec
}
EOF

cat << 'EOF' > /home/user/ingester/processor/processor.go
package processor

import (
	"log-ingester/parser"
)

func Process(records []parser.Record) ([]parser.Record, error) {
	// ASSERTION TO BE ADDED HERE:
	// for _, r := range records {
	//     if r.UserAgent == "" { return nil, fmt.Errorf("validation failed: empty user agent") }
	// }
	return records, nil
}
EOF

cat << 'EOF' > /home/user/ingester/main.go
package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"log-ingester/parser"
	"log-ingester/processor"
)

func main() {
	inPath := flag.String("input", "", "input log file")
	outPath := flag.String("output", "", "output json file")
	flag.Parse()

	if *inPath == "" || *outPath == "" {
		fmt.Println("Usage: go run main.go -input <in> -output <out>")
		os.Exit(1)
	}

	f, err := os.Open(*inPath)
	if err != nil {
		panic(err)
	}
	defer f.Close()

	var records []parser.Record
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		if line != "" {
			records = append(records, parser.ParseLine(line))
		}
	}

	processed, err := processor.Process(records)
	if err != nil {
		panic(err)
	}

	outF, err := os.Create(*outPath)
	if err != nil {
		panic(err)
	}
	defer outF.Close()

	enc := json.NewEncoder(outF)
	enc.SetIndent("", "  ")
	if err := enc.Encode(processed); err != nil {
		panic(err)
	}
}
EOF

# Create normal batch
touch /home/user/data/batch_491.log
for i in $(seq 1 999); do
	echo "ts=2023-10-01T12:00:00Z ip=192.168.1.$(($i%255)) ua=\"Mozilla/5.0\"" >> /home/user/data/batch_491.log
done

# The crushing line (triggering out of bounds in parser)
# A quote immediately after an unescaped condition or a missing end quote.
echo "ts=2023-10-01T12:00:00Z ip=192.168.1.1 ua=\"Mozilla/5.0 \\\"CrashMe\\\"" >> /home/user/data/batch_491.log

for i in $(seq 1001 10000); do
	echo "ts=2023-10-01T12:00:00Z ip=192.168.1.$(($i%255)) ua=\"Mozilla/5.0\"" >> /home/user/data/batch_491.log
done

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
