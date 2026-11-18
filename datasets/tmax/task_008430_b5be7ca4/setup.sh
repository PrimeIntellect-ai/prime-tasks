#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go coreutils bash
pip3 install pytest

mkdir -p /home/user/app

# Create the memory dump
dd if=/dev/urandom of=/home/user/dump.bin bs=1K count=1024 2>/dev/null
echo "some random string RECOVERY_TOKEN_a7f939b2e11c94d0 corrupted memory" >> /home/user/dump.bin
dd if=/dev/urandom >> /home/user/dump.bin bs=1K count=1024 2>/dev/null

# Create data.csv (1000 lines)
cat << 'EOF' > /home/user/app/generate_csv.sh
#!/bin/bash
for i in {1..1000}; do
    if [ $i -eq 642 ]; then
        echo "metric_x,14.5000000"
    else
        # Safe values
        echo "metric_x,2.0000000"
    fi
done
EOF
chmod +x /home/user/app/generate_csv.sh
/home/user/app/generate_csv.sh > /home/user/app/data.csv
rm /home/user/app/generate_csv.sh

# Create main.go
cat << 'EOF' > /home/user/app/main.go
package main

import (
	"encoding/csv"
	"fmt"
	"os"
	"strconv"
)

// computeMetric calculates an iterative metric.
// BUG: Uses float32 which lacks the precision to converge for certain values (like 14.5)
// when the tolerance is set to 1e-7. It oscillates and triggers the assertion panic.
func computeMetric(val float32) float32 {
	var x float32 = val
	for i := 0; i < 1000; i++ {
		next := 0.5 * (x + val/x)
		diff := x - next
		if diff < 0 {
			diff = -diff
		}
		if diff < 1e-7 {
			return next
		}
		x = next
	}
	panic(fmt.Sprintf("Assertion failed: Convergence failure for input %f", val))
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: go run main.go <file.csv>")
		os.Exit(1)
	}

	file, err := os.Open(os.Args[1])
	if err != nil {
		panic(err)
	}
	defer file.Close()

	reader := csv.NewReader(file)
	records, err := reader.ReadAll()
	if err != nil {
		panic(err)
	}

	var total float32
	for _, record := range records {
		val, err := strconv.ParseFloat(record[1], 32)
		if err != nil {
			panic(err)
		}
		total += computeMetric(float32(val))
	}

	fmt.Printf("%.4f\n", total)
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
