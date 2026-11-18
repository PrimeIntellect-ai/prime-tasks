#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr cmake build-essential curl libssl-dev pkg-config cargo rustc gcc
    pip3 install pytest pillow

    mkdir -p /app/project/src
    mkdir -p /verifier/corpus/evil
    mkdir -p /verifier/corpus/clean
    mkdir -p /opt/legacy_ffi/libs/

    # Create legacy_parser.py
    cat << 'EOF' > /app/legacy_parser.py
# legacy parser
def parse(log):
    pass
EOF

    # Create CMakeLists.txt
    cat << 'EOF' > /app/project/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(HybridProject)

# PLACEHOLDER_LIB_PATH
set(LIB_DIR "/wrong/path")

add_executable(main main.cpp)
target_link_directories(main PRIVATE ${LIB_DIR})
target_link_libraries(main PRIVATE core_ffi)
EOF

    # Create main.cpp
    cat << 'EOF' > /app/project/main.cpp
extern "C" int ffi_func();
int main() {
    return ffi_func();
}
EOF

    # Create Rust lib.rs with intentional borrow checker error
    cat << 'EOF' > /app/project/src/lib.rs
#[no_mangle]
pub extern "C" fn ffi_func() -> i32 {
    let mut s = String::from("hello");
    let r1 = &s;
    let r2 = &mut s; // Intentional error
    0
}
EOF

    # Create a dummy shared library in /opt/legacy_ffi/libs/
    cat << 'EOF' > /tmp/dummy.c
int ffi_func() { return 0; }
EOF
    gcc -shared -fPIC -o /opt/legacy_ffi/libs/libcore_ffi.so /tmp/dummy.c

    # Generate image using Python
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 50), 'Library deployment target: /opt/legacy_ffi/libs/', fill=(0, 0, 0))
img.save('/app/build_arch.png')
"

    # Create dummy logs
    echo "Build successful" > /verifier/corpus/clean/log1.txt
    echo "Warning: unused variable" > /verifier/corpus/clean/log2.txt

    echo "[ERROR] link failed; rm -rf /" > /verifier/corpus/evil/log1.txt
    echo "error[E0499]: cannot borrow \`s\` as mutable more than once at a time" > /verifier/corpus/evil/log2.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app /verifier /opt
