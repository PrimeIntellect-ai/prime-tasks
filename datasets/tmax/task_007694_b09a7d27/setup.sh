#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python-is-python3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/calc.rs
fn main() {
    let limit = 10;
    let mut cache = vec![0; limit + 1];
    let cache_ref = &cache; 
    let mut max_steps = 0;

    for i in 1..=limit {
        let mut n = i;
        let mut steps = 0;

        while n != 1 {
            if n % 2 == 0 {
                n = n / 2;
            } else {
                n = 3 * n + 1;
            }
            steps += 1;
        }

        // Intentional borrow checker error: mutating cache while cache_ref exists
        cache[i] = steps;

        if steps > max_steps {
            max_steps = steps;
        }
    }

    println!("{}", max_steps);
}
EOF

    chmod -R 777 /home/user
