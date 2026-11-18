#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    # Create app directory and audio file
    mkdir -p /app
    python3 -c "import wave; import struct; f = wave.open('/app/field_report.wav', 'w'); f.setnchannels(1); f.setsampwidth(2); f.setframerate(44100); f.writeframes(struct.pack('<h', 0)); f.close()"

    # Create mock transcribe tool
    cat << 'EOF' > /usr/local/bin/transcribe
#!/bin/bash
echo '{"id": "A-47", "reported_name": "John Doe", "expected_name": "Jon Doe", "confidence": 0.92, "transcript_text": "Agent 47 checking in. Target sighted."}'
EOF
    chmod +x /usr/local/bin/transcribe

    # Create oracle directory
    mkdir -p /opt/oracle

    # Write oracle Go program
    cat << 'EOF' > /opt/oracle/etl_processor_oracle.go
package main

import (
	"encoding/csv"
	"encoding/json"
	"io"
	"os"
	"strconv"
	"unicode/utf8"
)

type Record struct {
	ID             string  `json:"id"`
	ReportedName   string  `json:"reported_name"`
	ExpectedName   string  `json:"expected_name"`
	Confidence     float64 `json:"confidence"`
	TranscriptText string  `json:"transcript_text"`
}

func levenshtein(s, t string) int {
	rs, rt := []rune(s), []rune(t)
	d := make([][]int, len(rs)+1)
	for i := range d {
		d[i] = make([]int, len(rt)+1)
	}
	for i := range d {
		d[i][0] = i
	}
	for j := range d[0] {
		d[0][j] = j
	}
	for j := 1; j <= len(rt); j++ {
		for i := 1; i <= len(rs); i++ {
			if rs[i-1] == rt[j-1] {
				d[i][j] = d[i-1][j-1]
			} else {
				min := d[i-1][j] + 1
				if d[i][j-1]+1 < min {
					min = d[i][j-1] + 1
				}
				if d[i-1][j-1]+1 < min {
					min = d[i-1][j-1] + 1
				}
				d[i][j] = min
			}
		}
	}
	return d[len(rs)][len(rt)]
}

func main() {
	dec := json.NewDecoder(os.Stdin)
	csvWriter := csv.NewWriter(os.Stdout)
	defer csvWriter.Flush()

	for {
		var r Record
		if err := dec.Decode(&r); err != nil {
			if err == io.EOF {
				break
			}
			continue
		}
		if r.Confidence < 0.85 || r.ID == "" {
			continue
		}
		dist := levenshtein(r.ReportedName, r.ExpectedName)
		tLen := utf8.RuneCountInString(r.TranscriptText)

		record := []string{
			r.ID,
			r.ReportedName,
			r.ExpectedName,
			strconv.Itoa(dist),
			strconv.Itoa(tLen),
		}
		csvWriter.Write(record)
		csvWriter.Flush()
	}
}
EOF

    # Compile the oracle
    cd /opt/oracle
    go build -o etl_processor_oracle etl_processor_oracle.go
    rm etl_processor_oracle.go

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
