#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go ffmpeg
    pip3 install pytest gTTS

    mkdir -p /app

    cat << 'EOF' > /tmp/oracle.go
package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

func parseFloats(s string) []float64 {
	parts := strings.Split(s, ",")
	res := make([]float64, len(parts))
	for i, p := range parts {
		res[i], _ = strconv.ParseFloat(p, 64)
	}
	return res
}

func parseInts(s string) []int {
	parts := strings.Split(s, ",")
	res := make([]int, len(parts))
	for i, p := range parts {
		res[i], _ = strconv.Atoi(p)
	}
	return res
}

func main() {
	if len(os.Args) != 4 {
		return
	}
	preds := parseFloats(os.Args[1])
	truths := parseFloats(os.Args[2])
	ages := parseInts(os.Args[3])

	var sum float64
	n := len(preds)

	for i := 0; i < n; i++ {
		diff := preds[i] - truths[i]
		sq := diff * diff

		var w float64
		if ages[i] < 18 {
			w = 2.5
		} else if ages[i] >= 18 && ages[i] <= 65 {
			w = 1.0
		} else {
			w = 1.8
		}

		sum += sq * w
	}

	res := sum / float64(n)
	fmt.Printf("%.5f", res)
}
EOF

    go build -o /app/oracle_evaluator /tmp/oracle.go

    cat << 'EOF' > /tmp/gen_audio.py
from gtts import gTTS

text = "Hello, this is the MLOps engineer. For our new model evaluation pipeline, you need to implement the Demographic Risk Metric in Go. The program should accept three command line arguments. Each argument is a comma separated list. The first is predictions, the second is ground truths, and the third is user ages. For each data point, calculate the squared difference between the prediction and the ground truth. Then, multiply this squared difference by a demographic weight. If the user age is strictly less than eighteen, the weight is two point five. If the age is between eighteen and sixty-five inclusive, the weight is one point zero. If the age is strictly greater than sixty-five, the weight is one point eight. Sum these weighted squared differences, and divide by the total number of data points. Print the final result formatted to exactly five decimal places."
tts = gTTS(text)
tts.save("/tmp/dictation.mp3")
EOF

    python3 /tmp/gen_audio.py
    ffmpeg -i /tmp/dictation.mp3 /app/metric_dictation.wav

    rm /tmp/oracle.go /tmp/gen_audio.py /tmp/dictation.mp3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
