#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/asset_optimizer
    cat << 'EOF' > /home/user/asset_optimizer/optimizer.go
package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"sync"
)

type Config struct {
	MaxPixels int     `json:"max_pixels"`
	MinAspect float64 `json:"min_aspect"`
	MaxAspect float64 `json:"max_aspect"`
}

type Output struct {
	Width  int `json:"Width"`
	Height int `json:"Height"`
	Area   int `json:"Area"`
}

type Result struct {
	W    int
	H    int
	Area int
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Missing config file")
		os.Exit(1)
	}

	data, err := ioutil.ReadFile(os.Args[1])
	if err != nil {
		panic(err)
	}

	var config Config
	json.Unmarshal(data, &config)

	results := make(chan Result, 1000)
	var wg sync.WaitGroup

	// Split search space
	workers := 4
	chunk := 5000 / workers

	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func(start, end int) {
			defer wg.Done()
			for w := start; w <= end; w++ {
				for h := 1; h <= w; h++ {
					area := w * h
					if area <= config.MaxPixels {
						aspect := float64(w) / float64(h)
						if aspect >= config.MinAspect && aspect <= config.MaxAspect {
							results <- Result{W: w, H: h, Area: area}
						}
					}
				}
			}
		}(i*chunk+1, (i+1)*chunk)
	}

	// BUG: missing goroutine to close(results) after wg.Wait()
	go func() {
		wg.Wait()
		// close(results) // This is what the agent needs to add
	}()

	best := Result{}
	for r := range results {
		if r.Area > best.Area {
			best = r
		}
	}

	out := Output{Width: best.W, Height: best.H, Area: best.Area}
	b, _ := json.Marshal(out)
	fmt.Println(string(b))
}
EOF

    cd /home/user/asset_optimizer && go mod init asset_optimizer

    chmod -R 777 /home/user
