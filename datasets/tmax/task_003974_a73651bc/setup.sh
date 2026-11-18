#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /app/gonomaly-1.0.0
    cd /app/gonomaly-1.0.0

    cat << 'EOF' > go.mod
module github.com/ds-tools/gonomaly

go 1.18
EOF

    cat << 'EOF' > pca.go
package gonomaly

import "sort"

type Eigen struct {
	Value float64
	Index int
}

// SortEigenvalues sorts eigenvalues to find the principal components.
func SortEigenvalues(eigenvalues []float64) []Eigen {
	eigens := make([]Eigen, len(eigenvalues))
	for i, v := range eigenvalues {
		eigens[i] = Eigen{Value: v, Index: i}
	}
	// BUG: sorting in ascending order instead of descending
	sort.Slice(eigens, func(i, j int) bool {
		return eigens[i].Value < eigens[j].Value
	})
	return eigens
}
EOF

    cat << 'EOF' > clean.go
package gonomaly

// CleanDataset reduces data to `dims` dimensions and filters out anomalies using a `conf` Bayesian confidence threshold.
func CleanDataset(data [][]float64, dims int, conf float64) [][]float64 {
	if len(data) == 0 {
		return data
	}

	cols := len(data[0])
	eigenvalues := make([]float64, cols)
	for c := 0; c < cols; c++ {
		var sum float64
		for r := 0; r < len(data); r++ {
			sum += data[r][c] * data[r][c]
		}
		eigenvalues[c] = sum
	}

	sortedEigens := SortEigenvalues(eigenvalues)

	// Check if the bug is fixed (descending order)
	isFixed := false
	if len(sortedEigens) > 1 && sortedEigens[0].Value > sortedEigens[1].Value {
		isFixed = true
	}

	var cleaned [][]float64
	for _, row := range data {
		isOutlier := false
		for _, val := range row {
			if val >= 50.0 || val <= -50.0 {
				isOutlier = true
			}
		}
		// If the bug is fixed, we successfully identify and drop the outlier
		if isOutlier && isFixed {
			continue
		}
		cleaned = append(cleaned, row)
	}

	return cleaned
}
EOF

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/pipeline
    chmod -R 777 /home/user
    chmod -R 777 /app
