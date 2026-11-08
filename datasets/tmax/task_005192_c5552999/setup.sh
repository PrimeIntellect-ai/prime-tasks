#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/data.fasta
>seq1
ATGCGTAATGCGTAATGCGTA
>seq2
CGTACGCCGTACGCCGTACGC
>seq3
GGCCTTAGGCCTTAGGCCTTA
>seq4
AATTCCGGAATTCCGGAATTCCGG
>seq5
GCGCGCGCGCGCGCGCGCGCGCGC
>seq6
TATATATATATATATATATATATA
>seq7
ACGTACGTACGTACGTACGTACGT
>seq8
GGGGCCCCGGGGCCCCGGGGCCCC
>seq9
AAAATTTTAAAATTTTAAAATTTT
>seq10
CCCGGGCCCGGGCCCGGGCCCGGG
EOF

    cat << 'EOF' > /home/user/gc_calc.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"
	"sync"
)

func calcWeight(seq string) float64 {
	w := 0.0
	for i, c := range seq {
		if c == 'G' || c == 'C' {
			w += 1.0 / float64(i+1)
		} else {
			w += 0.5 / float64(i+1)
		}
	}
	return w
}

func main() {
	file, err := os.Open("/home/user/data.fasta")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	var seqs []string
	var currentSeq strings.Builder

	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, ">") {
			if currentSeq.Len() > 0 {
				seqs = append(seqs, currentSeq.String())
				currentSeq.Reset()
			}
		} else {
			currentSeq.WriteString(line)
		}
	}
	if currentSeq.Len() > 0 {
		seqs = append(seqs, currentSeq.String())
	}

	var totalWeight float64
	var wg sync.WaitGroup
	ch := make(chan float64, len(seqs))

	for _, s := range seqs {
		wg.Add(1)
		go func(seq string) {
			defer wg.Done()
			ch <- calcWeight(seq)
		}(s)
	}

	go func() {
		wg.Wait()
		close(ch)
	}()

	// The reduction currently happens non-deterministically
	for w := range ch {
		totalWeight += w
	}

	fmt.Printf("%.10f\n", totalWeight)
}
EOF

    chmod 644 /home/user/data.fasta
    chmod 644 /home/user/gc_calc.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
