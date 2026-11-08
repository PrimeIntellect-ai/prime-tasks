#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user

    # Create malicious zip file
    mkdir -p /tmp/zip_setup/sub
    echo '{"version": 1}' > /tmp/zip_setup/main.json
    echo '{"db": "mysql"}' > /tmp/zip_setup/sub/db.json
    echo '{"pwned": true}' > /tmp/zip_setup/escaped.json

    cd /tmp/zip_setup
    python3 -c "
import zipfile
with zipfile.ZipFile('/home/user/update.zip', 'w') as z:
    z.write('main.json', 'main.json')
    z.write('sub/db.json', 'sub/db.json')
    z.write('escaped.json', '../../../home/user/escaped.json')
"

    # Create vulnerable Go script
    cat << 'EOF' > /home/user/extract.go
package main

import (
    "archive/zip"
    "fmt"
    "io"
    "os"
    "path/filepath"
)

func main() {
    src := "/home/user/update.zip"
    dest := "/home/user/configs/"

    r, err := zip.OpenReader(src)
    if err != nil {
        panic(err)
    }
    defer r.Close()

    os.MkdirAll(dest, 0755)

    for _, f := range r.File {
        // VULNERABLE: No check if fpath is outside dest
        fpath := filepath.Join(dest, f.Name)

        if f.FileInfo().IsDir() {
            os.MkdirAll(fpath, os.ModePerm)
            continue
        }

        if err = os.MkdirAll(filepath.Dir(fpath), os.ModePerm); err != nil {
            panic(err)
        }

        outFile, err := os.OpenFile(fpath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, f.Mode())
        if err != nil {
            panic(err)
        }

        rc, err := f.Open()
        if err != nil {
            panic(err)
        }

        _, err = io.Copy(outFile, rc)
        outFile.Close()
        rc.Close()
        if err != nil {
            panic(err)
        }
    }
    fmt.Println("Extraction complete.")
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
