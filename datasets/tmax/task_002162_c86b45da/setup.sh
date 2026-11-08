#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl tar
    pip3 install --default-timeout=100 pytest

    # Install Go
    curl -LO https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
    rm go1.21.6.linux-amd64.tar.gz

    # Setup vendored package
    mkdir -p /app/vendor/securezip
    cat << 'EOF' > /app/vendor/securezip/go.mod
module securezip

go 1.21
EOF

    cat << 'EOF' > /app/vendor/securezip/securezip.go
package securezip

import (
	"archive/zip"
	"io"
	"os"
	"path/filepath"
)

func Extract(r io.ReaderAt, size int64, dest string) error {
	zr, err := zip.NewReader(r, size)
	if err != nil {
		return err
	}

	for _, f := range zr.File {
		target, err := SanitizePath(dest, f.Name)
		if err != nil {
			return err
		}

		if f.FileInfo().IsDir() {
			os.MkdirAll(target, 0755)
			continue
		}

		os.MkdirAll(filepath.Dir(target), 0755)

		rc, err := f.Open()
		if err != nil {
			return err
		}

		dstFile, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, f.Mode())
		if err != nil {
			rc.Close()
			return err
		}

		_, err = io.Copy(dstFile, rc)
		dstFile.Close()
		rc.Close()
		if err != nil {
			return err
		}
	}
	return nil
}
EOF

    # Create secure utils.go first to build oracle
    cat << 'EOF' > /app/vendor/securezip/utils.go
package securezip
import (
    "fmt"
    "os"
    "path/filepath"
    "strings"
)
func SanitizePath(dest, filename string) (string, error) {
    dest = filepath.Clean(dest)
    target := filepath.Join(dest, filename)
    if !strings.HasPrefix(target, dest+string(os.PathSeparator)) {
        return "", fmt.Errorf("zip slip detected")
    }
    return target, nil
}
EOF

    # Build oracle
    mkdir -p /app/oracle/src
    cat << 'EOF' > /app/oracle/src/go.mod
module oracle

go 1.21

require securezip v0.0.0
replace securezip => /app/vendor/securezip
EOF

    cat << 'EOF' > /app/oracle/src/main.go
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"securezip"
)

type FileInfo struct {
	Name string `json:"name"`
	Size int    `json:"size"`
}

type Response struct {
	Success bool       `json:"success,omitempty"`
	Files   []FileInfo `json:"files"`
	Error   string     `json:"error,omitempty"`
}

func main() {
	input, err := io.ReadAll(os.Stdin)
	if err != nil {
		fmt.Printf(`{"error": "%s"}`+"\n", err.Error())
		return
	}

	dest := "/tmp/config_dest"
	os.RemoveAll(dest)
	os.MkdirAll(dest, 0755)
	defer os.RemoveAll(dest)

	err = securezip.Extract(bytes.NewReader(input), int64(len(input)), dest)
	if err != nil {
		fmt.Printf(`{"error": "%s"}`+"\n", err.Error())
		return
	}

	var files []FileInfo
	err = filepath.Walk(dest, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if !info.IsDir() && strings.HasSuffix(info.Name(), ".json") {
			content, err := os.ReadFile(path)
			if err == nil && json.Valid(content) {
				files = append(files, FileInfo{
					Name: info.Name(),
					Size: int(info.Size()),
				})
			}
		}
		return nil
	})

	if err != nil {
		fmt.Printf(`{"error": "%s"}`+"\n", err.Error())
		return
	}

	sort.Slice(files, func(i, j int) bool {
		return files[i].Name < files[j].Name
	})

	if files == nil {
		files = []FileInfo{}
	}

	resp := Response{
		Success: true,
		Files:   files,
	}
	out, _ := json.Marshal(resp)
	fmt.Println(string(out))
}
EOF

    cd /app/oracle/src
    /usr/local/go/bin/go build -o /app/oracle/extract_config_oracle main.go
    cd /
    rm -rf /app/oracle/src

    # Now make utils.go vulnerable for the agent
    cat << 'EOF' > /app/vendor/securezip/utils.go
package securezip
import "path/filepath"
// SanitizePath is supposed to prevent zip slip
func SanitizePath(dest, filename string) (string, error) {
    // VULNERABILITY: No sanitization
    return filepath.Join(dest, filename), nil
}
EOF

    # Setup user and home
    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/go.mod
module extract_config

go 1.21

require securezip v0.0.0
replace securezip => /app/vendor/securezip
EOF

    chmod -R 777 /home/user
