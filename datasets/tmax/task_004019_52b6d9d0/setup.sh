#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/repo

    cat << 'EOF' > /home/user/repo/interpreter.rs
use std::env;
use std::fs;

fn process_opcodes(opcodes: String) {
    let mut state: u8 = 0;
    for c in opcodes.chars() {
        if c == '^' {
            // XOR state with 42
            state = state ^ 42;
        } else if c == '.' {
            print!("{}", state as char);
        } else {
            // just set state to the char's byte value
            state = c as u8;
        }
    }
    println!("");
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: interpreter <file>");
        std::process::exit(1);
    }

    let content = fs::read_to_string(&args[1]).expect("Failed to read file");

    // Borrow checker error introduced here:
    // process_opcodes consumes the String, but we try to print it afterwards.
    process_opcodes(content);

    // The PR author left this debug print which causes a "borrow of moved value" error
    eprintln!("Finished executing {} bytes of bytecode.", content.len());
}
EOF

    cat << 'EOF' > /home/user/repo/build.sh
#!/bin/bash

echo "Compiling Rust interpreter..."
rustc /home/user/repo/interpreter.rs -o /home/user/repo/interpreter_bin
echo "Build successful."
EOF

    cat << 'EOF' > /home/user/repo/run.sh
#!/bin/bash
if [ ! -f "/home/user/repo/interpreter_bin" ]; then
    echo "Interpreter binary not found. Run build.sh first."
    exit 1
fi
/home/user/repo/interpreter_bin "$1"
EOF

    cat << 'EOF' > /home/user/repo/data.enc
i^.e^.x^.x^.o^.i^.~^.
EOF

    chmod +x /home/user/repo/build.sh
    chmod +x /home/user/repo/run.sh

    chmod -R 777 /home/user
