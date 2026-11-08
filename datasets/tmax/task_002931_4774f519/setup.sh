#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go tesseract-ocr fonts-dejavu-core
    pip3 install pytest numpy Pillow

    mkdir -p /app
    mkdir -p /home/user/sim

    # Generate the network_params.png image
    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw, ImageFont

img = Image.new('RGB', (800, 400), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = """0 -> 1 : 0.3333333333333333
0 -> 2 : 0.6666666666666666
1 -> 0 : 0.1
1 -> 3 : 0.9
2 -> 3 : 1.0
3 -> 0 : 1.0"""

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 32)
except:
    font = ImageFont.load_default()

d.text((20, 20), text, fill=(0, 0, 0), font=font)
img.save('/app/network_params.png')
EOF
    python3 /tmp/make_image.py

    # Create the main.go file
    cat << 'EOF' > /home/user/sim/main.go
package main

import (
	"fmt"
	"sync"
)

func main() {
	// PLACEHOLDER: Replace with extracted weights
	matrix := map[int]map[int]float64{
		0: {1: 0.5, 2: 0.5},
		1: {0: 0.5, 3: 0.5},
		2: {3: 1.0},
		3: {0: 1.0},
	}

	state := []float64{1.0, 0.0, 0.0, 0.0}

	for iter := 0; iter < 1000; iter++ {
		nextState := []float64{0.0, 0.0, 0.0, 0.0}
		var wg sync.WaitGroup
		var mu sync.Mutex

		for src, edges := range matrix {
			for dst, weight := range edges {
				wg.Add(1)
				go func(s, d int, w float64) {
					defer wg.Done()
					val := state[s] * w
					mu.Lock()
					nextState[d] += val
					mu.Unlock()
				}(src, dst, weight)
			}
		}
		wg.Wait()
		state = nextState
	}

	for _, v := range state {
		fmt.Printf("%.16f\n", v)
	}
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
