#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq diffutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project_v1/src
    mkdir -p /home/user/project_v2/src

    cat << 'EOF' > /home/user/project_v1/src/main.rs
fn main() {
    let x = 10;
    let y = 20;
    println!("Sum is {}", x + y);

    // Old implementation
    let z = calculate_heavy(x, y);
    println!("Heavy: {}", z);
}

fn calculate_heavy(a: i32, b: i32) -> i32 {
    a * b * 2
}
EOF

    cat << 'EOF' > /home/user/project_v2/src/main.rs
fn main() {
    let x = 10;
    let y = 20;
    println!("Sum is {}", x + y);

    // New optimized implementation
    let z = calculate_light(x, y);
    println!("Light: {}", z);
    println!("Done");
}

fn calculate_light(a: i32, b: i32) -> i32 {
    a + b
}
EOF

    cat << 'EOF' > /home/user/project_v2/api_specs.txt
REST GET /api/v1/health
GRAPHQL type Query
REST POST /api/v1/users
REST DELETE /api/v1/users/:id
GRAPHQL type Mutation
GRAPHQL type UserProfile
EOF

    chmod -R 777 /home/user
