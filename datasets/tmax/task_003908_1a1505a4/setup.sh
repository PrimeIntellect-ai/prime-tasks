#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user/stat_sim
    cd /home/user/stat_sim
    cargo init --bin

    cat << 'EOF' > /home/user/stat_sim/src/main.rs
fn simulate(start: i8) -> i32 {
    let mut x: i8 = start;
    let mut steps = 0;

    while x < 100 && steps < 10_000 {
        // Calculate difference to target (100)
        let diff = 100_i8.wrapping_sub(x);

        let step = diff / 2;

        x = x.wrapping_add(step);
        steps += 1;
    }

    steps
}

fn main() {
    let mut total_steps = 0;
    for start_val in -100..=50 {
        total_steps += simulate(start_val);
    }
    println!("{}", total_steps);
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/stat_sim
    chmod -R 777 /home/user
