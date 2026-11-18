#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang git
    pip3 install pytest cryptography

    # Create directories
    mkdir -p /app/telemparser/testdata
    mkdir -p /testdata
    mkdir -p /home/user/workspace/statstool

    # Initialize Go module
    cd /app/telemparser
    go mod init telemparser

    # Create parser.go (Commit 1: Correct int64 sum)
    cat << 'EOF' > parser.go
package telemparser

import (
	"crypto/aes"
	"crypto/cipher"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"io/ioutil"
)

func CalculateMean(filename, hexKey string) (float64, error) {
	key, err := hex.DecodeString(hexKey)
	if err != nil {
		return 0, err
	}

	data, err := ioutil.ReadFile(filename)
	if err != nil {
		return 0, err
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return 0, err
	}

	aesgcm, err := cipher.NewGCM(block)
	if err != nil {
		return 0, err
	}

	nonceSize := aesgcm.NonceSize()
	if len(data) < nonceSize {
		return 0, errors.New("ciphertext too short")
	}

	nonce, ciphertext := data[:nonceSize], data[nonceSize:]
	plaintext, err := aesgcm.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return 0, err
	}

	if len(plaintext)%4 != 0 {
		return 0, errors.New("invalid data length")
	}

	var sum int64 = 0
	count := len(plaintext) / 4

	for i := 0; i < len(plaintext); i += 4 {
		val := int32(binary.BigEndian.Uint32(plaintext[i : i+4]))
		sum += int64(val)
	}

	if count == 0 {
		return 0, nil
	}
	return float64(sum) / float64(count), nil
}
EOF

    # Create key.txt
    echo -n "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef" > key.txt

    # Git setup
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    # Commit 1
    git add go.mod parser.go key.txt
    git commit -m "Initial commit"

    # Commit 2
    git rm key.txt
    git commit -m "Remove hardcoded key"

    # Commit 3 (Introduce bug)
    sed -i 's/var sum int64 = 0/var sum int32 = 0/g' parser.go
    sed -i 's/sum += int64(val)/sum += val/g' parser.go
    git add parser.go
    git commit -m "Optimize memory usage"

    # Create encrypted test files
    cat << 'EOF' > /tmp/gen_data.py
import os
import struct
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

key = bytes.fromhex("deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
aesgcm = AESGCM(key)

def create_enc_file(filename, values):
    plaintext = b"".join(struct.pack(">i", v) for v in values)
    nonce = os.urandom(12)
    ciphertext = aesgcm.encrypt(nonce, plaintext, None)
    os.makedirs(os.path.dirname(filename), exist_ok=True)
    with open(filename, "wb") as f:
        f.write(nonce + ciphertext)

# 400 values: 300 * 14502394 + 100 * 14502395
# Sum = 5800957700 (Overflows int32)
# Mean = 14502394.25
values = [14502394] * 300 + [14502395] * 100
create_enc_file("/app/telemparser/testdata/samples.bin.enc", values)
create_enc_file("/testdata/eval.bin.enc", values)
EOF
    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app /testdata
    chmod -R 777 /home/user /app /testdata
