#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang curl
    pip3 install pytest

    mkdir -p /app/vendored/ziputil
    cat << 'EOF' > /app/vendored/ziputil/go.mod
module github.com/broken/ziputil

go 1.20
EOF

    cat << 'EOF' > /app/vendored/ziputil/ziputil.go
package ziputil

import (
	"archive/zip"
	"io"
	"os"
	"path/filepath"
)

func Extract(zipPath, dest string) error {
	r, err := zip.OpenReader(zipPath)
	if err != nil {
		return err
	}
	defer r.Close()

	for _, f := range r.File {
		fpath := filepath.Join(dest, f.Name)
		if f.FileInfo().IsDir() {
			os.MkdirAll(fpath, os.ModePerm)
			continue
		}

		if err := os.MkdirAll(filepath.Dir(fpath), os.ModePerm); err != nil {
			return err
		}

		outFile, err := os.OpenFile(fpath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, f.Mode())
		if err != nil {
			return err
		}

		rc, err := f.Open()
		if err != nil {
			return err
		}

		_, err = io.Copy(outFile, rc)
		outFile.Close()
		rc.Close()
		if err != nil {
			return err
		}
	}
	return nil
}
EOF

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/incoming
    mkdir -p /home/user/extracted
    mkdir -p /home/user/www
    mkdir -p /home/user/docserver

    chmod -R 777 /home/user
    chmod -R 777 /app
