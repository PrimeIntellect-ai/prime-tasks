#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    mkdir -p /home/user/data_parser/src
    cd /home/user/data_parser

    cat << 'EOF' > src/lib.rs
use std::ffi::CString;
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn process_data() -> *mut c_char {
    let data = r#"{"status": "success", "payload": {"id": 8472, "msg": "hello"}}"#;
    let c_str = CString::new(data).unwrap();
    // Broken: returning pointer to dropped value
    c_str.as_ptr() as *mut c_char
}
EOF

    cat << 'EOF' > parser.py
import ctypes
import json
import os

# Load library
lib_path = os.path.join(os.path.dirname(__file__), 'librust_parser.so')
lib = ctypes.CDLL(lib_path)

lib.process_data.restype = ctypes.c_char_p

# Retrieve data
raw_data = lib.process_data()

# Parse and write to output (Broken)
data = raw_data.decode('utf-8')
# Need to parse json and write payload.id
with open("output.json", "w") as f:
    f.write(data)
EOF

    cat << 'EOF' > ci.sh
#!/bin/bash

# TODO: Compile the rust library
# rustc ...

# TODO: Run the python script
# python3 parser.py
EOF
    chmod +x ci.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
