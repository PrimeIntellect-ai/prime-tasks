#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go git
    pip3 install pytest

    # Set up the broken vendored package
    mkdir -p /app/go-nlp-utils
    cat << 'EOF' > /app/go-nlp-utils/go.mod
module github.com/dataeng/go-nlp-util

go 1.18
EOF

    cat << 'EOF' > /app/go-nlp-utils/tokenizer.go
package nlp

import (
	"regexp"
	"strings"
)

var punctRe = regexp.MustCompile(`[^\w\s]`)

func NormalizeAndTokenize(text string) string {
	normalized := norm.NFC.String(text)
	lower := strings.ToLower(normalized)
	noPunct := punctRe.ReplaceAllString(lower, "")
	return strings.ReplaceAll(noPunct, " ", "_")
}
EOF

    cat << 'EOF' > /app/go-nlp-utils/tokenizer_test.go
package nlp

import "testing"

func TestNormalizeAndTokenize(t *testing.T) {
	in := "Hello, World!"
	expected := "hello_world"
	if out := NormalizeAndTokenize(in); out != expected {
		t.Errorf("Expected %q, got %q", expected, out)
	}
}
EOF

    # Set up the oracle binary
    mkdir -p /opt/oracle/src
    cat << 'EOF' > /opt/oracle/src/main.go
package main

import (
	"encoding/csv"
	"fmt"
	"io"
	"os"
	"regexp"
	"strconv"
	"strings"
	"golang.org/x/text/unicode/norm"
)

var punctRe = regexp.MustCompile(`[^\w\s]`)

func NormalizeAndTokenize(text string) string {
	normalized := norm.NFC.String(text)
	lower := strings.ToLower(normalized)
	noPunct := punctRe.ReplaceAllString(lower, "")
	return strings.ReplaceAll(noPunct, " ", "_")
}

func main() {
	reader := csv.NewReader(os.Stdin)
	writer := csv.NewWriter(os.Stdout)
	defer writer.Flush()

	_, err := reader.Read()
	if err != nil {
		return
	}
	writer.Write([]string{"id", "lang", "clean_text", "score"})

	var lastScore float64 = 0.00

	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			continue
		}

		id := record[0]
		lang := record[2]
		rawText := record[3]
		scoreStr := record[4]

		if lang == "" {
			lang = "unknown"
		}

		var score float64
		if scoreStr == "" {
			score = lastScore
		} else {
			s, err := strconv.ParseFloat(scoreStr, 64)
			if err == nil {
				score = s
				lastScore = s
			} else {
				score = lastScore
			}
		}

		cleanText := NormalizeAndTokenize(rawText)
		writer.Write([]string{id, lang, cleanText, fmt.Sprintf("%.2f", score)})
	}
}
EOF

    cd /opt/oracle/src
    go mod init oracle
    go get golang.org/x/text/unicode/norm
    go build -o /opt/oracle/etl_oracle main.go
    rm -rf /opt/oracle/src

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
