#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest websockets

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/processor.go
package main

/*
#include <stdlib.h>
*/
import "C"
import (
	"strings"
	"sync"
)

//export ProcessData
func ProcessData(input *C.char) *C.char {
	goStr := C.GoString(input)
	words := strings.Fields(goStr)
	out := make([]string, len(words))

	var wg sync.WaitGroup
	for i, w := range words {
		wg.Add(1)
		go func(idx int, word string) {
			defer wg.Done()
			runes := []rune(strings.ToUpper(word))
			for j, k := 0, len(runes)-1; j < k; j, k = j+1, k-1 {
				runes[j], runes[k] = runes[k], runes[j]
			}
			out[idx] = string(runes)
		}(i, w)
	}
	wg.Wait()

	return C.CString(strings.Join(out, " "))
}

func main() {}
EOF

    chmod -R 777 /home/user
