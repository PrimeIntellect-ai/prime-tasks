#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/integrate.go
package main

import "C"
import (
	"sync"
)

//export CalculatePi
func CalculatePi(steps C.int) C.double {
	n := int(steps)
	numWorkers := 4
	chunkSize := n / numWorkers

	var wg sync.WaitGroup
	results := make(chan float64, numWorkers)
	stepSize := 1.0 / float64(n)

	for w := 0; w < numWorkers; w++ {
		wg.Add(1)
		go func(workerID int) {
			defer wg.Done()
			start := workerID * chunkSize
			end := start + chunkSize
			if workerID == numWorkers-1 {
				end = n
			}

			var localSum float64
			for i := start; i < end; i++ {
				x := (float64(i) + 0.5) * stepSize
				localSum += 4.0 / (1.0 + x*x)
			}
			results <- localSum * stepSize
		}(w)
	}

	wg.Wait()
	close(results)

	var totalPi float64
	for res := range results {
		totalPi += res
	}

	return C.double(totalPi)
}

func main() {}
EOF

    chmod -R 777 /home/user
