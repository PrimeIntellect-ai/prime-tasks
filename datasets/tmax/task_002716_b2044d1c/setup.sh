#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/qa-env/wsprocessor/sorter
    mkdir -p /home/user/qa-env/wsprocessor/differ
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil
    mkdir -p /app

    cat << 'EOF' > /home/user/qa-env/wsprocessor/go.mod
module wsprocessor
go 1.20
EOF

    cat << 'EOF' > /home/user/qa-env/wsprocessor/sorter/sorter.go
package sorter
import "wsprocessor/differ"

type Sequence struct {
    Data []int
}

func SortAndDiff(seq Sequence) []int {
    // mock implementation
    return differ.CalculateGaps(seq.Data)
}
EOF

    cat << 'EOF' > /home/user/qa-env/wsprocessor/differ/differ.go
package differ
import "wsprocessor/sorter"

func CalculateGaps(data []int) []int {
    return []int{}
}

func Analyze(seq sorter.Sequence) bool {
    return len(seq.Data) > 0
}
EOF

    cat << 'EOF' > /tmp/oracle.go
package main
import (
    "fmt"
    "io"
    "os"
    "sort"
)
func main() {
    var nums []int
    for {
        var n int
        _, err := fmt.Scan(&n)
        if err == io.EOF {
            break
        }
        nums = append(nums, n)
    }
    if len(nums) < 2 {
        os.Exit(0)
    }
    sort.Ints(nums)
    for i := 1; i < len(nums); i++ {
        diff := nums[i] - nums[i-1]
        if diff <= 0 || diff > 10 {
            os.Exit(1)
        }
    }
    os.Exit(0)
}
EOF

    go build -ldflags="-s -w" -o /app/seq_oracle /tmp/oracle.go
    rm /tmp/oracle.go

    echo "15 5 20 10" > /home/user/corpora/clean/1.txt
    echo "1 2 3 4" > /home/user/corpora/clean/2.txt
    echo "10 20 30" > /home/user/corpora/clean/3.txt

    echo "5 15 26" > /home/user/corpora/evil/1.txt
    echo "5 10 10 15" > /home/user/corpora/evil/2.txt
    echo "1 12" > /home/user/corpora/evil/3.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
