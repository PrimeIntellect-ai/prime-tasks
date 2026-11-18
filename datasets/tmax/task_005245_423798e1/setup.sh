#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest requests

    mkdir -p /app
    cat << 'EOF' > /tmp/translator.go
package main

import (
	"encoding/base64"
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Print("Unknown")
		return
	}
	locale := os.Args[1]
	b64Text := os.Args[2]

	decoded, err := base64.StdEncoding.DecodeString(b64Text)
	if err != nil {
		fmt.Print("Unknown")
		return
	}
	text := string(decoded)

	if locale == "es-ES" {
		switch text {
		case "Welcome":
			fmt.Print("Bienvenido")
		case "Warning":
			fmt.Print("Advertencia")
		case "Idle":
			fmt.Print("Inactivo")
		case "Error":
			fmt.Print("Error")
		default:
			fmt.Print("Unknown")
		}
	} else if locale == "fr-FR" {
		switch text {
		case "Welcome":
			fmt.Print("Bienvenue")
		case "Warning":
			fmt.Print("Avertissement")
		case "Idle":
			fmt.Print("Inactif")
		case "Error":
			fmt.Print("Erreur")
		default:
			fmt.Print("Unknown")
		}
	} else {
		fmt.Print("Unknown")
	}
}
EOF

    go build -ldflags="-s -w" -o /app/loc_translator /tmp/translator.go
    chmod +x /app/loc_translator
    rm /tmp/translator.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
