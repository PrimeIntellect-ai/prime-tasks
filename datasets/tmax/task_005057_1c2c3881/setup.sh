#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/polyglot
    cat << 'EOF' > /home/user/polyglot/validator.rs
fn get_token<'a>() -> &'a str {
    let token = String::from("VALID");
    &token
}
fn main() {
    let t = get_token();
    println!("{}", t);
}
EOF

    cat << 'EOF' > /home/user/polyglot/parser.c
#include <string.h>
#include <stdio.h>
void parse(const char* input) {
    char buffer[256];
    strcpy(buffer, input); // Vulnerable
    printf("Parsed: %s\n", buffer);
}
EOF

    cat << 'EOF' > /home/user/polyglot/logger.go
package main
import (
    "fmt"
    "time"
)
var LogMap = make(map[int]string)
func logReq(id int, msg string) {
    LogMap[id] = msg // Race condition
}
func main() {
    for i := 0; i < 10; i++ {
        go logReq(i, "req")
    }
    time.Sleep(1 * time.Second)
    fmt.Println("Done")
}
EOF

    chmod -R 777 /home/user
