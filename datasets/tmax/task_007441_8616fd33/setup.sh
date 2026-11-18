#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip patch gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/check.go
package main

import (
	"fmt"
	"sync"
)

func worker(id int, val int, wg *sync.WaitGroup, ch chan int) {
	defer wg.Done()
	ch <- id * val
}

func main() {
	var wg sync.WaitGroup
	ch := make(chan int, 3)

	wg.Add(3)
	go worker(1, 10, &wg, ch)
	go worker(2, 20, &wg, ch)
	go worker(3, 30, &wg, ch)

	wg.Wait()
	close(ch)

	sum := 0
	for v := range ch {
		sum += v
	}
	fmt.Printf("Total: %d\n", sum)
}
EOF

    cat << 'EOF' > /home/user/update.patch
--- check.go
+++ check.go
@@ -15,9 +15,9 @@
 	ch := make(chan int, 3)

 	wg.Add(3)
-	go worker(1, 10, &wg, ch)
-	go worker(2, 20, &wg, ch)
-	go worker(3, 30, &wg, ch)
+	go worker(1, 15, &wg, ch)
+	go worker(2, 25, &wg, ch)
+	go worker(3, 35, &wg, ch)

 	wg.Wait()
 	close(ch)
EOF

    chmod -R 777 /home/user
