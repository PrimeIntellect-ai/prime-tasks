#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg golang gawk
    pip3 install pytest

    mkdir -p /oracle /app

    # 1. Create a dummy video (e.g., 60 frames of random grayscale)
    ffmpeg -f lavfi -i color=c=gray:s=32x32:r=10 -vframes 60 -c:v libx264 /app/experiment_run.mp4

    # 2. Create telemetry.csv
    echo "frame_index,temperature" > /app/telemetry.csv
    for i in {0..59}; do
      temp=$(awk -v i=$i 'BEGIN {print 50 + 5 * sin(i/5)}')
      echo "$i,$temp" >> /app/telemetry.csv
    done

    # 3. Create the Oracle
    cat << 'EOF' > /oracle/main.go
package main

import (
    "bufio"
    "fmt"
    "math"
    "os"
    "strconv"
    "strings"
)

func main() {
    scanner := bufio.NewScanner(os.Stdin)
    var window [10][2]float64
    count := 0

    for scanner.Scan() {
        line := scanner.Text()
        if line == "" {
            continue
        }
        parts := strings.Split(line, ",")
        if len(parts) != 2 {
            continue
        }
        b, _ := strconv.ParseFloat(strings.TrimSpace(parts[0]), 64)
        t, _ := strconv.ParseFloat(strings.TrimSpace(parts[1]), 64)

        window[count%10] = [2]float64{b, t}
        count++

        if count >= 10 {
            var sumB, sumT float64
            for i := 0; i < 10; i++ {
                sumB += window[i][0]
                sumT += window[i][1]
            }
            meanB := sumB / 10.0
            meanT := sumT / 10.0

            var varB, varT float64
            for i := 0; i < 10; i++ {
                varB += (window[i][0] - meanB) * (window[i][0] - meanB)
                varT += (window[i][1] - meanT) * (window[i][1] - meanT)
            }
            sB := math.Sqrt(varB / 9.0)
            sT := math.Sqrt(varT / 9.0)

            lowerT := meanT - 1.96*(sT/math.Sqrt(10))
            upperT := meanT + 1.96*(sT/math.Sqrt(10))

            anomaly := 0
            if b > meanB+1.5*sB {
                anomaly = 1
            }

            fmt.Printf("%.4f,%.4f,%.4f,%d\n", meanB, lowerT, upperT, anomaly)
        }
    }
}
EOF
    cd /oracle && go build -o feature_extractor_oracle main.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
