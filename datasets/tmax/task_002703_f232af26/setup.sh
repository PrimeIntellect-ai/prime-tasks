#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang ffmpeg
    pip3 install pytest

    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=20:size=640x480:rate=30 /app/diagnostic_feed.mp4

    mkdir -p /home/user/workspace/vid_service/
    cat << 'EOF' > /home/user/workspace/vid_service/main.go
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os/exec"
)

type extractReq struct {
	VideoPath string  `json:"video_path"`
	T0        float64 `json:"t0"`
	Delta     float64 `json:"delta"`
	N         int     `json:"n"`
}

type extractResp struct {
	frames []string `json:"frames"` // BUG: unexported field
}

func extractHandler(w http.ResponseWriter, r *http.Request) {
	var req extractReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	var resp extractResp
	resp.frames = make([]string, 0)

	for i := 0; i < req.N; i++ {
		// BUG: Wrong formula (t0 + i * delta instead of t0 + i*i*delta)
		t := req.T0 + float64(i)*req.Delta 

		// BUG: Incomplete ffmpeg command. Missing correct output format and exact seek flags
		cmd := exec.Command("ffmpeg", "-i", req.VideoPath, "-ss", fmt.Sprintf("%f", t), "-vframes", "1", "-f", "rawvideo", "-")
		var out bytes.Buffer
		cmd.Stdout = &out
		if err := cmd.Run(); err != nil {
			http.Error(w, fmt.Sprintf("ffmpeg error: %v", err), http.StatusInternalServerError)
			return
		}

		// BUG: Raw bytes cast to string instead of base64 encoding
		resp.frames = append(resp.frames, string(out.Bytes()))
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func main() {
	http.HandleFunc("/extract", extractHandler)
	http.ListenAndServe(":8080", nil)
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
