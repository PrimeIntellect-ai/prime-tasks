#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/corpus.txt
the quick brown fox jumps over the lazy dog
a quick brown dog jumps
machine learning is a subset of artificial intelligence
data science encompasses machine learning and statistics
artificial intelligence and machine learning are the future
statistics is the foundation of data science
deep learning is a type of machine learning
natural language processing deals with text
tokenization is the first step in natural language processing
machine learning models require high quality data
EOF

    cat << 'EOF' > /home/user/prep_data.go
package main

import (
	"bufio"
	"fmt"
	"math"
	"os"
	"strings"
)

func tokenize(text string) []string {
	text = strings.ToLower(text)
	return strings.Fields(text)
}

func getTF(tokens []string, vocab []string) []float64 {
	tf := make([]float64, len(vocab))
	total := len(tokens)
	if total == 0 {
		return tf
	}
	counts := make(map[string]int)
	for _, t := range tokens {
		counts[t]++
	}
	for i, v := range vocab {
		// BUG: integer division here evaluates to 0
		tf[i] = float64(counts[v] / total)
	}
	return tf
}

func cosineSimilarity(a, b []float64) float64 {
	var dotProduct, normA, normB float64
	for i := 0; i < len(a); i++ {
		dotProduct += a[i] * b[i]
		normA += a[i] * a[i]
		normB += b[i] * b[i]
	}
	if normA == 0 || normB == 0 {
		return 0
	}
	return dotProduct / (math.Sqrt(normA) * math.Sqrt(normB))
}

func main() {
	file, err := os.Open("/home/user/corpus.txt")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	var docs [][]string
	vocabMap := make(map[string]bool)
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		tokens := tokenize(scanner.Text())
		docs = append(docs, tokens)
		for _, t := range tokens {
			vocabMap[t] = true
		}
	}

	var vocab []string
	for k := range vocabMap {
		vocab = append(vocab, k)
	}

	var vectors [][]float64
	for _, doc := range docs {
		vectors = append(vectors, getTF(doc, vocab))
	}

	bestI, bestJ := -1, -1
	var maxSim float64 = -1.0

	for i := 0; i < len(vectors); i++ {
		for j := i + 1; j < len(vectors); j++ {
			sim := cosineSimilarity(vectors[i], vectors[j])
			if sim > maxSim {
				maxSim = sim
				bestI = i
				bestJ = j
			}
		}
	}

	out, _ := os.Create("/home/user/result.txt")
	defer out.Close()
	fmt.Fprintf(out, "%d,%d,%.4f\n", bestI, bestJ, maxSim)
}
EOF

    chmod -R 777 /home/user
