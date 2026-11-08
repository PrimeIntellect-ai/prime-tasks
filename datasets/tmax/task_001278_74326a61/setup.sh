#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ode_sim/src

    cat << 'EOF' > /home/user/ode_sim/Cargo.toml
[package]
name = "ode_sim"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/ode_sim/src/main.rs
fn mat_vec_mul(m: &[[f64; 3]; 3], v: &[f64; 3]) -> [f64; 3] {
    let mut out = [0.0; 3];
    for i in 0..3 {
        out[i] = m[i][0]*v[0] + m[i][1]*v[1] + m[i][2]*v[2];
    }
    out
}

fn main() {
    let m = [
        [4.0, 12.0, -16.0],
        [12.0, 37.0, -43.0],
        [-16.0, -43.0, 98.0],
    ];
    let b = [2.0, 11.0, -1.0];

    // Cholesky L of M:
    // L = [[2, 0, 0], [6, 1, 0], [-8, 5, 3]]
    // L * y0 = b  => y0 = [1.0, 5.0, -6.0]
    let mut y = [1.0, 5.0, -6.0]; 

    let mut t = 0.0;
    let t_end = 0.5;
    let mut h = 0.001;
    let tol = 1e-5;

    while t < t_end {
        if t + h > t_end {
            h = t_end - t;
        }

        // k1 = f(t, y) = -M*y
        let my = mat_vec_mul(&m, &y);
        let k1 = [-my[0], -my[1], -my[2]];

        let y_euler = [
            y[0] + h * k1[0],
            y[1] + h * k1[1],
            y[2] + h * k1[2],
        ];

        let my_euler = mat_vec_mul(&m, &y_euler);
        let k2 = [-my_euler[0], -my_euler[1], -my_euler[2]];

        let y_heun = [
            y[0] + h * 0.5 * (k1[0] + k2[0]),
            y[1] + h * 0.5 * (k1[1] + k2[1]),
            y[2] + h * 0.5 * (k1[2] + k2[2]),
        ];

        // Error norm
        let mut err = 0.0_f64;
        for i in 0..3 {
            err += (y_heun[i] - y_euler[i]).powi(2);
        }
        err = err.sqrt() + 1e-12; // avoid div by zero

        // BUG IS HERE: Inverted error adaptation
        let h_new = h * (err / tol).powf(0.5);

        if err <= tol {
            t += h;
            y = y_heun;
        }

        // Update step size with safety bounds
        h = h_new.clamp(1e-6, 0.1);
    }

    println!("{:.5} {:.5} {:.5}", y[0], y[1], y[2]);
}
EOF

    chmod -R 777 /home/user
