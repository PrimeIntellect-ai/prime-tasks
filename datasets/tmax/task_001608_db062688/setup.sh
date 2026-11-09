#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/rust_parser
    mkdir -p /home/user/payloads

    cat << 'EOF' > /home/user/rust_parser/state.rs
pub enum State {
    INIT,
    SAFE,
    DANGER,
    ACCEPT,
}

pub fn transition(current: State, action: &str) -> Option<State> {
    match (current, action) {
        (State::INIT, "SANITIZE") => Some(State::SAFE),
        (State::INIT, "LOAD") => Some(State::DANGER),
        (State::SAFE, "EVAL") => Some(State::SAFE),
        (State::SAFE, "FINISH") => Some(State::ACCEPT),
        (State::DANGER, "SANITIZE") => Some(State::SAFE),
        (State::DANGER, "FINISH") => Some(State::ACCEPT),
        // Web Security Rule: EVAL in DANGER or INIT is an injection attempt.
        // Handled in parser.rs
        _ => None,
    }
}
EOF

    cat << 'EOF' > /home/user/rust_parser/parser.rs
use crate::state::{State, transition};

// Broken lifetime definition
pub struct Parser<'a, 'b> {
    state: State,
    payload: &'a str,
    // intentional lifetime mismatch error setup for scenario
    last_action: &'b str, 
}

impl<'a, 'b> Parser<'a, 'b> {
    pub fn new(payload: &'a str) -> Self {
        Parser {
            state: State::INIT,
            payload,
            last_action: "",
        }
    }

    pub fn parse(&mut self) -> Result<(), &'static str> {
        let mut lines = self.payload.lines();

        let version_line = lines.next().ok_or("INVALID_STATE")?;
        if !version_line.starts_with("VERSION v") {
            return Err("INVALID_STATE");
        }

        // Version logic implies: 1.2.0 <= version < 2.0.0

        let size_line = lines.next().ok_or("INVALID_STATE")?;
        // size logic

        for line in lines {
            let parts: Vec<&str> = line.splitn(2, ':').collect();
            if parts.len() != 2 { return Err("INVALID_STATE"); }
            let action = parts[0];

            if action == "EVAL" && !matches!(self.state, State::SAFE) {
                return Err("REJECTED_INJECTION");
            }

            if let Some(new_state) = transition(self.state, action) {
                self.state = new_state;
            } else {
                return Err("INVALID_STATE");
            }
        }

        if matches!(self.state, State::ACCEPT) {
            Ok(())
        } else {
            Err("INVALID_STATE")
        }
    }
}
EOF

    cat << 'EOF' > /home/user/rust_parser/main.rs
mod state;
mod parser;

fn main() {
    // Fails to compile
    println!("Compilation failed.");
}
EOF

    cat << 'EOF' > /home/user/payloads/payload_a.swp
VERSION v1.2.5
SIZE 2
SANITIZE:input_data
FINISH:done
EOF

    cat << 'EOF' > /home/user/payloads/payload_b.swp
VERSION v2.0.1
SIZE 2
SANITIZE:input_data
FINISH:done
EOF

    cat << 'EOF' > /home/user/payloads/payload_c.swp
VERSION v1.9.9
SIZE 2
LOAD:malicious_data
EVAL:run_code
EOF

    cat << 'EOF' > /home/user/payloads/payload_d.swp
VERSION v1.2.0
SIZE 3
LOAD:data
SANITIZE:clean
EVAL:run_code
EOF

    cat << 'EOF' > /home/user/payloads/payload_e.swp
VERSION v1.1.9
SIZE 2
SANITIZE:data
FINISH:done
EOF

    cat << 'EOF' > /home/user/payloads/payload_f.swp
VERSION v1.5.0
SIZE 2
UNKNOWN:data
FINISH:done
EOF

    cat << 'EOF' > /home/user/expected_results.log
payload_a.swp: VALID
payload_b.swp: INVALID_VERSION
payload_c.swp: REJECTED_INJECTION
payload_d.swp: INVALID_STATE
payload_e.swp: INVALID_VERSION
payload_f.swp: INVALID_STATE
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
