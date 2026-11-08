#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl cargo
    pip3 install pytest fastapi uvicorn redis python-multipart

    mkdir -p /home/user/pipeline/incoming
    mkdir -p /home/user/pipeline/extracted
    mkdir -p /home/user/pipeline/manifests
    mkdir -p /home/user/pipeline/uploader
    mkdir -p /home/user/pipeline/processor/src

    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    cat << 'EOF' > /home/user/pipeline/uploader/app.py
from fastapi import FastAPI, UploadFile, File
import redis
import os
import shutil

app = FastAPI()
r = redis.Redis(host='localhost', port=6379, db=0)

@app.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    file_location = f"/home/user/pipeline/incoming/{file.filename}"
    with open(file_location, "wb+") as file_object:
        shutil.copyfileobj(file.file, file_object)
    r.rpush('dataset_queue', file_location)
    return {"info": f"file '{file.filename}' saved at '{file_location}'"}
EOF

    cat << 'EOF' > /home/user/pipeline/processor/Cargo.toml
[package]
name = "processor"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/pipeline/processor/src/main.rs
fn main() {
    println!("Hello, world!");
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
