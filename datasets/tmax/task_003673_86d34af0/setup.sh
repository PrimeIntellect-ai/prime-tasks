#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang tesseract-ocr imagemagick
    pip3 install pytest

    mkdir -p /app
    convert -background white -fill black -font Courier -pointsize 72 label:'137' /app/amplitude.png

    cat << 'EOF' > /tmp/oracle.go
package main
import ("bufio"; "fmt"; "math"; "os"; "strings")
func main() {
	amplitude := 137.0
	scanner := bufio.NewScanner(os.Stdin)
	total, gc := 0, 0
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, ">") { continue }
		for _, char := range line {
			c := strings.ToUpper(string(char))
			if c == "A" || c == "C" || c == "G" || c == "T" {
				total++
				if c == "G" || c == "C" { gc++ }
			}
		}
	}
	if total == 0 {
		fmt.Printf("0.000000\n")
	} else {
		ratio := float64(gc) / float64(total)
		fmt.Printf("%.6f\n", amplitude * math.Sin(ratio*math.Pi))
	}
}
EOF
    go build -o /app/oracle /tmp/oracle.go
    chmod +x /app/oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
