#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/num_calc/src
    cd /home/user/num_calc

    cat << 'EOF' > Cargo.toml
[package]
name = "num_calc"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > src/lib.rs
pub fn left_riemann_sum(start: f64, end: f64, steps: usize) -> f64 {
    let step_size = (end - start) / (steps as f64);
    let mut sum = 0.0;

    let mut current_x = start as f32;
    let step_f32 = step_size as f32;

    // Bug: off-by-one (<= steps instead of < steps)
    for _ in 0..=steps {
        sum += (current_x * current_x) as f64 * step_size;
        // Bug: precision loss using f32 accumulator
        current_x += step_f32;
    }
    sum
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_integral_precision() {
        let result = left_riemann_sum(0.0, 100.0, 1_000_000);
        // Expected for integral of x^2 from 0 to 100 is 333333.333...
        // With left riemann sum and 1M steps, it should be highly accurate.
        // Precision loss and off-by-one make it fail completely.
        assert!((result - 333333.3333).abs() < 1.0, "Result was {}", result);
    }
}
EOF

    # Generate the CI build log
    cargo test &> /home/user/ci_build.log || true

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
