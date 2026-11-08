#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/math_feature
    cd /home/user/math_feature

    cat << 'EOF' > prime_worker.go
package main

import "C"
import (
	"fmt"
	"strings"
)

//export Factorize
func Factorize(n int64) *C.char {
	factors := []string{}
	var d int64 = 2
	for n > 1 {
		for n%d == 0 {
			factors = append(factors, fmt.Sprintf("%d", d))
			n /= d
		}
		d++
		if d*d > n {
			if n > 1 {
				factors = append(factors, fmt.Sprintf("%d", n))
			}
			break
		}
	}
	return C.CString(strings.Join(factors, ","))
}

func main() {}
EOF

    cat << 'EOF' > main.py
import ctypes
import os

lib_path = os.path.join(os.path.dirname(__file__), 'libprimes.so')
lib = ctypes.cdll.LoadLibrary(lib_path)

lib.Factorize.argtypes = [ctypes.c_int64]
lib.Factorize.restype = ctypes.c_char_p

result = lib.Factorize(1234567890)
decoded_result = result.decode('utf-8')

with open('output.txt', 'w') as f:
    f.write(decoded_result + "\n")
EOF

    cat << 'EOF' > build.sh
#!/bin/bash
cd /home/user/math_feature

# BROKEN BUILD COMMAND - does not build a shared library
go build -o libprimes.so prime_worker.go

# Run python script
python3 main.py
EOF
    chmod +x build.sh

    go mod init math_feature

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
