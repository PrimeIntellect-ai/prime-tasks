#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/project/queues

    cat << 'EOF' > /home/user/project/limiter_logic.rs
struct Queue {
    id: usize,
    capacity: usize,
    files: Vec<String>,
}

fn organize_requests(incoming_files: Vec<String>) {
    let mut queues: Vec<Queue> = Vec::new();
    let mut current_queue = Queue { id: 1, capacity: 5, files: Vec::new() };

    // Bug: moving incoming_files into iterator, but if we wanted to reuse strings or
    // specifically the bug here is moving the `file_name` String into the vector 
    // and then trying to print it afterwards without cloning.
    for file_name in incoming_files {
        if current_queue.files.len() >= current_queue.capacity {
            queues.push(current_queue);
            current_queue = Queue { id: queues.len() + 1, capacity: 5, files: Vec::new() };
        }

        current_queue.files.push(file_name);
        // OWNERSHIP BUG HERE: file_name was moved into the vector above.
        println!("Moved file: {}", file_name); 
    }
    queues.push(current_queue);
}
fn main() {}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
