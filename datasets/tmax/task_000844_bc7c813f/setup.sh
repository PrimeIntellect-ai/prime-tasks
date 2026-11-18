#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang binutils xxd
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /app/bin
    mkdir -p /home/user/tracker

    cat << 'EOF' > /tmp/legacy.go
package main

import (
	"archive/tar"
	"encoding/binary"
	"io"
	"os"
	"regexp"
	"strings"
	"time"
)

func main() {
	magic := make([]byte, 4)
	if _, err := io.ReadFull(os.Stdin, magic); err != nil {
		return
	}
	if string(magic) != "TRKV" {
		return
	}
	var count uint16
	if err := binary.Read(os.Stdin, binary.LittleEndian, &count); err != nil {
		return
	}
	tw := tar.NewWriter(os.Stdout)
	defer tw.Close()
	re := regexp.MustCompile(`PASS=\S+`)
	for i := 0; i < int(count); i++ {
		var nameLen uint8
		if err := binary.Read(os.Stdin, binary.LittleEndian, &nameLen); err != nil {
			return
		}
		nameBytes := make([]byte, nameLen)
		if _, err := io.ReadFull(os.Stdin, nameBytes); err != nil {
			return
		}
		var contentLen uint32
		if err := binary.Read(os.Stdin, binary.LittleEndian, &contentLen); err != nil {
			return
		}
		contentBytes := make([]byte, contentLen)
		if _, err := io.ReadFull(os.Stdin, contentBytes); err != nil {
			return
		}
		contentStr := string(contentBytes)
		contentStr = re.ReplaceAllString(contentStr, "PASS=REDACTED")
		contentStr = strings.ReplaceAll(contentStr, "\r\n", "\n")
		outBytes := []byte(contentStr)
		hdr := &tar.Header{
			Name:     string(nameBytes),
			Mode:     0644,
			Uid:      1000,
			Gid:      1000,
			Size:     int64(len(outBytes)),
			ModTime:  time.Unix(1000000000, 0),
			Uname:    "config",
			Gname:    "config",
			Typeflag: tar.TypeReg,
		}
		if err := tw.WriteHeader(hdr); err != nil {
			return
		}
		if _, err := tw.Write(outBytes); err != nil {
			return
		}
	}
}
EOF

    cd /tmp
    go build -o /app/bin/legacy_tracker legacy.go
    strip /app/bin/legacy_tracker
    rm /tmp/legacy.go

    chmod -R 777 /home/user
