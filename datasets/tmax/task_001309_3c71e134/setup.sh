#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr cargo
pip3 install pytest Pillow

mkdir -p /app/rust_math/src /app/rust_math/benches

cat << 'EOF' > /tmp/make_img.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color='white')
d = ImageDraw.Draw(img)
d.text((10,10), "ENCODING_MULTIPLIER = 17\nMODULUS = 256", fill=(0,0,0))
img.save('/app/legacy_formula.png')
EOF
python3 /tmp/make_img.py

cat << 'EOF' > /app/rust_math/Cargo.toml
[package]
name = "rust_math"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

cat << 'EOF' > /app/rust_math/src/lib.rs
#[no_mangle]
pub extern "C" fn process_bytes(input: *const u8, len: usize, multiplier: u8, output: *mut u8) {
    let slice = unsafe { std::slice::from_raw_parts(input, len) };
    let out_slice = unsafe { std::slice::from_raw_parts_mut(output, len) };

    let temp_vec: Vec<u8> = slice.iter().map(|&b| b.wrapping_mul(multiplier)).collect();
    // Intentional borrow issue simulating junior dev mistake: returning reference to local
    let bad_ref = &temp_vec;
    out_slice.copy_from_slice(bad_ref);
}
EOF

cat << 'EOF' > /app/server.py
import BaseHTTPServer
import json
import ctypes
import base64

class RequestHandler(BaseHTTPServer.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/encode':
            auth = self.headers.getheader('Authorization')
            if auth != 'Bearer migrate-token-2024':
                self.send_response(401)
                self.end_headers()
                return

            length = int(self.headers.getheader('content-length'))
            body = self.rfile.read(length)
            data = json.loads(body)['data']

            # Python 2 string mixing
            lib = ctypes.CDLL('./rust_math/target/release/librust_math.so')

            # Need multiplier from image
            multiplier = 17 # Agent must get this from OCR

            in_buf = ctypes.create_string_buffer(data)
            out_buf = ctypes.create_string_buffer(len(data))

            lib.process_bytes(in_buf, len(data), multiplier, out_buf)

            enc = base64.b64encode(out_buf.raw)

            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'result': enc}))

if __name__ == '__main__':
    server = BaseHTTPServer.HTTPServer(('127.0.0.1', 8080), RequestHandler)
    server.serve_forever()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
