#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest matplotlib pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sim_engine/src
    cd /home/user/sim_engine

    cat << 'EOF' > Cargo.toml
[package]
name = "sim_engine"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > src/main.rs
mod integrator;
mod graph;

use graph::SystemGraph;

fn main() {
    let mut system = SystemGraph::new();
    // Simple 1D harmonic oscillator with mass=1, k=1
    // Exact solution: x(t) = cos(t)
    system.add_node(1.0, 0.0);

    let t_end = 10.0;
    let mut t = 0.0;
    let mut dt = 0.1;
    let tolerance = 1e-4;

    println!("time,node1_x,node1_v");
    println!("0.000,1.000,0.000");

    while t < t_end {
        let (dt_actual, new_state) = integrator::step(&system, t, dt, tolerance);
        system.set_state(new_state);
        t += dt_actual;
        dt = dt_actual; // Use adapted step size for next iteration

        // Print at roughly 0.5 intervals
        if (t * 10.0).round() % 5.0 == 0.0 {
            let state = system.get_state();
            println!("{:.3},{:.5},{:.5}", t, state[0], state[1]);
        }
    }
}
EOF

    cat << 'EOF' > src/graph.rs
pub struct SystemGraph {
    // [x, v]
    pub state: [f64; 2],
}

impl SystemGraph {
    pub fn new() -> Self {
        SystemGraph { state: [0.0, 0.0] }
    }

    pub fn add_node(&mut self, x: f64, v: f64) {
        self.state = [x, v];
    }

    pub fn get_state(&self) -> [f64; 2] {
        self.state
    }

    pub fn set_state(&mut self, state: [f64; 2]) {
        self.state = state;
    }

    // Returns [dx/dt, dv/dt]
    pub fn derivatives(&self, state: &[f64; 2]) -> [f64; 2] {
        let x = state[0];
        let v = state[1];
        let a = -1.0 * x; // k = 1, m = 1
        [v, a]
    }
}
EOF

    cat << 'EOF' > src/integrator.rs
use crate::graph::SystemGraph;

pub fn step(system: &SystemGraph, _t: f64, mut dt: f64, tolerance: f64) -> (f64, [f64; 2]) {
    let state = system.get_state();

    loop {
        // Euler step (order 1)
        let d1 = system.derivatives(&state);
        let e1_x = state[0] + d1[0] * dt;
        let e1_v = state[1] + d1[1] * dt;

        // Midpoint step (order 2)
        let m_x = state[0] + d1[0] * (dt / 2.0);
        let m_v = state[1] + d1[1] * (dt / 2.0);
        let d2 = system.derivatives(&[m_x, m_v]);

        let e2_x = state[0] + d2[0] * dt;
        let e2_v = state[1] + d2[1] * dt;

        // Error estimate
        let err_x = (e2_x - e1_x).abs();
        let err_v = (e2_v - e1_v).abs();
        let error = err_x.max(err_v) + 1e-10;

        // BUG: Inverted adaptation logic. 
        // Should be the inverse of the line below.
        let scale = error / tolerance; 

        // Adaptive step size adjustment
        let dt_new = dt * scale.powf(0.5);

        if error <= tolerance {
            return (dt, [e2_x, e2_v]);
        } else {
            // Reject step, try again with smaller dt (but bug makes it larger!)
            // To prevent infinite loop in the buggy state, cap dt
            dt = dt_new.min(2.0);
            if dt >= 2.0 {
                return (dt, [f64::NAN, f64::NAN]);
            }
        }
    }
}
EOF

    cat << 'EOF' > /home/user/reference_data.csv
time,node1_x,node1_v
0.000,1.00000,0.00000
0.500,0.87758,-0.47943
1.000,0.54030,-0.84147
1.500,0.07074,-0.99749
2.000,-0.41615,-0.90930
2.500,-0.80114,-0.59847
3.000,-0.98999,-0.14112
3.500,-0.93646,0.35078
4.000,-0.65364,0.75680
4.500,-0.21080,0.97753
5.000,0.28366,0.95892
5.500,0.70867,0.70554
6.000,0.96017,0.27942
6.500,0.97659,-0.21512
7.000,0.75390,-0.65699
7.500,0.34664,-0.93800
8.000,-0.14550,-0.98936
8.500,-0.60201,-0.79849
9.000,-0.91113,-0.41212
9.500,-0.99717,0.07515
10.000,-0.83907,0.54402
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
