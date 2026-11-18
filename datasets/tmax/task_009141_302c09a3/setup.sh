#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc diffutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/merger.rs
fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: merger <file1> <file2>");
        std::process::exit(1);
    }

    let content1 = std::fs::read_to_string(&args[1]).unwrap();
    let content2 = std::fs::read_to_string(&args[2]).unwrap();

    let mut lines = Vec::new();
    for line in content1.lines() { lines.push(line); }
    for line in content2.lines() { lines.push(line); }

    lines.sort();

    let header = String::from("--- MERGED LOGS ---");
    print_header(header);

    // Borrow checker bug: `header` was moved into print_header, can't be used here.
    println!("(End of {})", header);

    for line in lines {
        println!("{}", line);
    }
}

fn print_header(h: String) {
    println!("{}", h);
}
EOF

    mkdir -p /home/user/tests/case1
    mkdir -p /home/user/tests/case2

    cat << 'EOF' > /home/user/tests/case1/input1.txt
apple
zebra
EOF

    cat << 'EOF' > /home/user/tests/case1/input2.txt
banana
EOF

    cat << 'EOF' > /home/user/tests/case1/expected.txt
--- MERGED LOGS ---
(End of --- MERGED LOGS ---)
apple
banana
zebra
EOF

    cat << 'EOF' > /home/user/tests/case2/input1.txt
log 2
EOF

    cat << 'EOF' > /home/user/tests/case2/input2.txt
log 1
log 3
EOF

    cat << 'EOF' > /home/user/tests/case2/expected.txt
--- MERGED LOGS ---
(End of --- MERGED LOGS ---)
log 1
log 2
log 3
EOF

    chmod -R 777 /home/user
