#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc cargo rustc curl wget binutils
pip3 install pytest requests

mkdir -p /app
cat << 'EOF' > /app/legacy_calc.c
#include <stdio.h>
#include <stdlib.h>

const char* cfg = "[SECRET_CONFIG] SEED=42 MULT=13 INC=7 MOD=1000003";

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    unsigned long long n = strtoull(argv[1], NULL, 10);
    unsigned long long val = 42;
    for (unsigned long long i = 0; i < n; i++) {
        val = (val * 13 + 7) % 1000003;
    }
    printf("%llu\n", val);
    return 0;
}
EOF
gcc -O2 /app/legacy_calc.c -o /app/legacy_calc
strip -s /app/legacy_calc
rm /app/legacy_calc.c

mkdir -p /home/user/math_service/src
cat << 'EOF' > /home/user/math_service/Cargo.toml
[package]
name = "math_service"
version = "0.1.0"
edition = "2015"

[dependencies]
actix-web = "0.0.0-invalid"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

cat << 'EOF' > /home/user/math_service/src/main.rs
use actix_web::{web, App, HttpServer, Responder, HttpResponse};
use serde::Deserialize;

#[derive(Deserialize)]
struct Info {
    n: u64,
}

fn calculate_sequence(n: u64) -> u64 {
    // TODO: Implement the correct logic using the extracted constants
    0
}

async fn calc(info: web::Query<Info>) -> impl Responder {
    let result = calculate_sequence(info.n);
    HttpResponse::Ok().json(serde_json::json!({ "result": result }))
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new().route("/calc", web::get().to(calc))
    })
    .bind("127.0.0.1:80")?
    .run()
    .await
}
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
