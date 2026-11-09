#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /app/math-daemon/src

    cat << 'EOF' > /app/math-daemon/Cargo.toml
[package]
name = "math-daemon"
version = "1.0.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
actix-web = "4.0"

[dev-dependencies]
proptest = "1.0"
EOF

    cat << 'EOF' > /app/math-daemon/src/main.rs
use actix_web::{web, App, HttpServer, HttpResponse, Responder};
use serde::{Deserialize, Serialize};
mod interpreter;

#[derive(Deserialize)]
struct EvalRequest {
    bytecode: Vec<u8>,
}

#[derive(Serialize)]
struct EvalResponse {
    result: Option<i32>,
    error: Option<String>,
}

async fn eval_handler(req: web::Json<EvalRequest>) -> impl Responder {
    match interpreter::eval(&req.bytecode) {
        Ok(res) => HttpResponse::Ok().json(EvalResponse { result: Some(res), error: None }),
        Err(e) => HttpResponse::Ok().json(EvalResponse { result: None, error: Some(e) }),
    }
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new().route("/eval", web::post().to(eval_handler))
    })
    .bind("127.0.0.1:9000")?
    .run()
    .await
}
EOF

    cat << 'EOF' > /app/math-daemon/src/interpreter.rs
pub fn eval(bytecode: &[u8]) -> Result<i32, String> {
    let mut stack: Vec<i32> = Vec::new();
    let mut i = 0;
    while i < bytecode.len() {
        match bytecode[i] {
            1 => { // push
                if i + 1 < bytecode.len() {
                    stack.push(bytecode[i+1] as i32);
                    i += 1;
                } else {
                    return Err("Unexpected EOF".to_string());
                }
            },
            4 => { // div
                if stack.len() < 2 {
                    return Err("Stack underflow".to_string());
                }
                let b = stack.pop().unwrap();
                let a = stack.pop().unwrap();
                stack.push(a / b);
            },
            _ => return Err("Unknown opcode".to_string()),
        }
        i += 1;
    }
    stack.pop().ok_or("Empty stack".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    proptest! {
        #[test]
        fn test_div_no_panic(a in -100i32..100, b in -100i32..100) {
            let bytecode = vec![1, a as u8, 1, b as u8, 4];
            let _ = eval(&bytecode);
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /app
    chmod -R 777 /home/user
