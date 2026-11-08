#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/logs /home/user/app /home/user/data

    cat << 'EOF' > /home/user/logs/service1.log
[2023-11-01 10:00:01 UTC] INFO Starting up
[2023-11-01 10:05:00 UTC] WARN CPU load high
EOF

    cat << 'EOF' > /home/user/logs/service2.log
2023/11/01 10:02:15 INFO Data received
2023/11/01 10:05:05 CRITICAL_ANOMALY Calculation NaN
EOF

    cat << 'EOF' > /home/user/logs/service3.log
Nov 1 10:01:00 service3 INFO Processing
Nov 1 10:06:00 service3 ERROR Timeout
EOF

    cat << 'EOF' > /home/user/data/input.json
{"batch_id": "A1", "readings": [1.5, 2.0, 3.5, 4.0]}
EOF

    cat << 'EOF' > /home/user/app/sensor_agg.go
package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"sync"
)

type InputData struct {
	BatchID  string    `json:"batch_id"`
	Readings []float64 `json:"readings"`
}

type OutputData struct {
	BatchID  string
	Variance float64
}

// Custom JSON marshaler with a bug (outputs hex instead of decimal for Variance)
func (o OutputData) MarshalJSON() ([]byte, error) {
	return []byte(fmt.Sprintf(`{"batch_id":"%s","variance":"%x"}`, o.BatchID, int64(o.Variance))), nil
}

func ComputeSumOfSquares(readings []float64) float64 {
	var sum float64
	var wg sync.WaitGroup

	for _, val := range readings {
		wg.Add(1)
		go func(v float64) {
			defer wg.Done()
			// BUG: Race condition
			sum += v * v
		}(val)
	}
	wg.Wait()
	return sum
}

func main() {
	if len(os.Args) < 2 {
		log.Fatal("Provide input file")
	}
	data, err := ioutil.ReadFile(os.Args[1])
	if err != nil {
		log.Fatal(err)
	}

	var in InputData
	if err := json.Unmarshal(data, &in); err != nil {
		log.Fatal(err)
	}

	variance := ComputeSumOfSquares(in.Readings)

	out := OutputData{
		BatchID:  in.BatchID,
		Variance: variance,
	}

	outBytes, _ := json.Marshal(out)
	fmt.Println(string(outBytes))
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
