#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev cargo rustc
    pip3 install pytest

    mkdir -p /home/user/app/vendor/libcsched
    mkdir -p /home/user/app/scheduler-api/src

    # libcsched/schedule.h
    cat << 'EOF' > /home/user/app/vendor/libcsched/schedule.h
#ifndef SCHEDULE_H
#define SCHEDULE_H
int calculate_schedule(const int* task_durations, int num_tasks, int* output_schedule);
#endif
EOF

    # libcsched/schedule.c
    cat << 'EOF' > /home/user/app/vendor/libcsched/schedule.c
#include "schedule.h"
int calculate_schedule(const int* task_durations, int num_tasks, int* output_schedule) {
    int current_time = 0;
    // Intentional off-by-one bug: i <= num_tasks
    for (int i = 0; i <= num_tasks; i++) {
        output_schedule[i] = current_time;
        current_time += task_durations[i];
    }
    return 0;
}
EOF

    # libcsched/Makefile
    cat << 'EOF' > /home/user/app/vendor/libcsched/Makefile
CC=gcc
CFLAGS=-Wall

all: libcsched.so

libcsched.so: schedule.o
	$(CC) -o libcsched.so schedule.o

schedule.o: schedule.c
	$(CC) $(CFLAGS) -c schedule.c

clean:
	rm -f *.o *.so
EOF

    # scheduler-api/Cargo.toml
    cat << 'EOF' > /home/user/app/scheduler-api/Cargo.toml
[package]
name = "scheduler-api"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.6"
tokio = { version = "1", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    # scheduler-api/src/main.rs (Skeleton)
    cat << 'EOF' > /home/user/app/scheduler-api/src/main.rs
use axum::{routing::post, Router};
use std::net::SocketAddr;

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/schedule", post(handle_schedule));

    let addr = SocketAddr::from(([127, 0, 0, 1], 8080));
    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .await
        .unwrap();
}

async fn handle_schedule() -> &'static str {
    "Not Implemented"
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
