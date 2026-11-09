#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.go
package main

import (
	"encoding/csv"
	"fmt"
	"io"
	"os"
	"strings"
)

func norm(s string) string {
	s = strings.ToLower(s)
	var b strings.Builder
	for _, c := range s {
		if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == ' ' {
			b.WriteRune(c)
		}
	}
	return b.String()
}

func min(a, b, c int) int {
	if a < b {
		if a < c {
			return a
		}
		return c
	}
	if b < c {
		return b
	}
	return c
}

func levenshtein(a, b string) int {
	ra, rb := []rune(a), []rune(b)
	n, m := len(ra), len(rb)
	if n == 0 {
		return m
	}
	if m == 0 {
		return n
	}
	d := make([][]int, n+1)
	for i := range d {
		d[i] = make([]int, m+1)
		d[i][0] = i
	}
	for j := 0; j <= m; j++ {
		d[0][j] = j
	}
	for i := 1; i <= n; i++ {
		for j := 1; j <= m; j++ {
			cost := 1
			if ra[i-1] == rb[j-1] {
				cost = 0
			}
			d[i][j] = min(d[i-1][j]+1, d[i][j-1]+1, d[i-1][j-1]+cost)
		}
	}
	return d[n][m]
}

func main() {
	r := csv.NewReader(os.Stdin)
	r.FieldsPerRecord = 4
	for {
		record, err := r.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			continue
		}
		id := record[0]
		en := norm(record[1])
		es := norm(record[2])
		fr := norm(record[3])

		fmt.Printf("%s\tes\t%s\t%d\n", id, es, levenshtein(en, es))
		fmt.Printf("%s\tfr\t%s\t%d\n", id, fr, levenshtein(en, fr))
	}
}
EOF

    go build -ldflags="-s -w" -o /app/loc_oracle /tmp/oracle.go
    rm /tmp/oracle.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
