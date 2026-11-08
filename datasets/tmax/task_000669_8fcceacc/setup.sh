#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang
pip3 install pytest

mkdir -p /home/user/pipeline
cd /home/user/pipeline

go mod init pipeline

cat << 'EOF' > /home/user/pipeline/fetcher.go
package pipeline

import (
	"context"
	"time"
)

func FetchData(ctx context.Context, urls []string) []string {
	ch := make(chan string) // BUG: unbuffered channel causes leak when ctx cancels
	for _, url := range urls {
		go func(u string) {
			// Simulating network delay
			time.Sleep(10 * time.Millisecond)
			ch <- u + "_data"
		}(url)
	}

	var results []string
	for range urls {
		select {
		case res := <-ch:
			results = append(results, res)
		case <-ctx.Done():
			return results // Leaks the remaining worker goroutines
		}
	}
	return results
}
EOF

cat << 'EOF' > /home/user/pipeline/fetcher_test.go
package pipeline

import (
	"context"
	"runtime"
	"testing"
	"time"
)

func TestFetchDataLeak(t *testing.T) {
	initialGoroutines := runtime.NumGoroutine()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Millisecond)
	defer cancel()

	urls := []string{"url1", "url2", "url3", "url4", "url5"}
	FetchData(ctx, urls)

	// Wait a bit to let any blocked goroutines settle
	time.Sleep(50 * time.Millisecond)

	finalGoroutines := runtime.NumGoroutine()
	if finalGoroutines > initialGoroutines+1 { // Allowing 1 for the test runner overhead
		t.Fatalf("Goroutine leak detected! Initial: %d, Final: %d", initialGoroutines, finalGoroutines)
	}
}
EOF

cat << 'EOF' > /home/user/pipeline/aggregator.py
def aggregate_prices(prices: list[float]) -> str:
    total = 0.0
    for p in prices:
        total += p
    # BUG: Float precision loss, e.g., 0.1 * 10 -> 0.9999999999999999
    return f"{total:.2f}"
EOF

cat << 'EOF' > /home/user/pipeline/test_aggregator.py
import unittest
import ast
from aggregator import aggregate_prices

class TestAggregator(unittest.TestCase):
    def test_uses_decimal(self):
        with open('aggregator.py', 'r') as f:
            source = f.read()

        self.assertIn('Decimal', source, "Must use the Decimal module for precision")

    def test_sum(self):
        self.assertEqual(aggregate_prices([0.1, 0.1, 0.1]), "0.30")
        self.assertEqual(aggregate_prices([1.01, 2.02]), "3.03")

if __name__ == '__main__':
    unittest.main()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
