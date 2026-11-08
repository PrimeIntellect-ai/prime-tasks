#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/locales

    cat << 'EOF' > /home/user/locales/en_US.csv
id,text
welcome,"Welcome, %s!"
multiline,"Line 1
Line 2"
count,"You have %d items"
bad_placeholder,"Score: %f"
EOF

    cat << 'EOF' > /home/user/locales/fr_FR.csv
id,translation
welcome,"Bienvenue, %s!"
multiline,"Ligne 1
Ligne 2"
count,"Vous avez %d articles"
bad_placeholder,"Score: %d"
EOF

    cat << 'EOF' > /home/user/locales/es_ES.csv
id,translation
welcome,"¡Bienvenido, %s!"
multiline,"Línea 1
Línea 2"
count,"Tienes artículos"
bad_placeholder,"Puntuación: %f"
EOF

    cat << 'EOF' > /home/user/processor.go
package main
import (
	"bufio"
	"fmt"
	"os"
	"strings"
)
func main() {
	// Broken naive implementation
	if len(os.Args) < 3 { return }
	f, _ := os.Open(os.Args[2])
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		parts := strings.Split(scanner.Text(), ",")
		if len(parts) >= 2 {
			fmt.Println(parts[0], parts[1])
		}
	}
}
EOF

    chmod -R 777 /home/user
