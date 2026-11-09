#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang openssl curl
    pip3 install pytest

    mkdir -p /home/user/service
    mkdir -p /home/user/important_data
    mkdir -p /home/user/restored_data

    # Create secret data
    echo "SECRET_DB_CREDENTIALS=prod_user:super_secret_password" > /home/user/important_data/secrets.env
    echo "Customer 1, Customer 2" > /home/user/important_data/customers.csv

    # Create flawed Go daemon
    cat << 'EOF' > /home/user/service/backup_daemon.go
package main

import (
	"archive/tar"
	"compress/gzip"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
)

func backupHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/gzip")
	w.Header().Set("Content-Disposition", `attachment; filename="backup.tar.gz"`)

	gz := gzip.NewWriter(w)
	defer gz.Close()

	tw := tar.NewWriter(gz)
	defer tw.Close()

	sourceDir := "/home/user/important_data"
	filepath.Walk(sourceDir, func(file string, fi os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		header, err := tar.FileInfoHeader(fi, fi.Name())
		if err != nil {
			return err
		}
		relPath, err := filepath.Rel(sourceDir, file)
		if err != nil {
			return err
		}
		if relPath == "." {
			return nil
		}
		header.Name = relPath

		if err := tw.WriteHeader(header); err != nil {
			return err
		}
		if !fi.Mode().IsRegular() {
			return nil
		}
		f, err := os.Open(file)
		if err != nil {
			return err
		}
		defer f.Close()
		_, err = io.Copy(tw, f)
		return err
	})
}

func main() {
	http.HandleFunc("/backup", backupHandler)
	// BUG: Running on HTTP instead of HTTPS, and no certs specified
	log.Fatal(http.ListenAndServe(":8443", nil))
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
