#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/sensor

    cat << 'EOF' > /home/user/sensor/sensor.go
package sensor

import (
	"encoding/base64"
	"encoding/json"
)

type Payload struct {
	Signature string    `json:"signature"`
	Readings  []float32 `json:"readings"`
}

func ProcessPayload(data []byte) (float64, []byte, error) {
	var p Payload
	if err := json.Unmarshal(data, &p); err != nil {
		return 0, nil, err
	}

	sig, err := base64.StdEncoding.DecodeString(p.Signature)
	if err != nil {
		return 0, nil, err
	}

	var sum float64
	for _, r := range p.Readings {
		sum += float64(r)
	}

	return sum, sig, nil
}
EOF

    cat << 'EOF' > /home/user/sensor/sensor_test.go
package sensor

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"math"
	mrand "math/rand"
	"testing"
	"time"
)

func TestProcessPayload(t *testing.T) {
	mrand.Seed(time.Now().UnixNano())

	for i := 0; i < 100; i++ {
		sig := make([]byte, 16)
		rand.Read(sig)
		sigStr := base64.URLEncoding.EncodeToString(sig)

		var readings []float64
		var expectedSum float64
		for j := 0; j < 50; j++ {
			val := mrand.Float64() * 50
			readings = append(readings, val)
			expectedSum += val
		}

		type testPayload struct {
			Signature string    `json:"signature"`
			Readings  []float64 `json:"readings"`
		}

		tp := testPayload{
			Signature: sigStr,
			Readings:  readings,
		}

		data, _ := json.Marshal(tp)

		actualSum, decodedSig, err := ProcessPayload(data)
		if err != nil {
			t.Fatalf("Failed to process payload: %v", err)
		}

		if string(decodedSig) != string(sig) {
			t.Fatalf("Signature mismatch")
		}

		if math.Abs(expectedSum-actualSum) > 1e-4 {
			t.Fatalf("Sum mismatch: expected %f, got %f", expectedSum, actualSum)
		}
	}
}
EOF

    cd /home/user/sensor
    go mod init sensor

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
