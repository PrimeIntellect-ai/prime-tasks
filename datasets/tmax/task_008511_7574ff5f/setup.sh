#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 << 'EOF'
import os
import struct

os.makedirs('/home/user/artifacts', exist_ok=True)
os.makedirs('/home/user/extracted', exist_ok=True)

# 1. Create a dummy ELF file (minimal valid 64-bit ELF header)
elf_header = bytearray(b'\x7fELF\x02\x01\x01\x00' + b'\x00'*8) # e_ident
elf_header += struct.pack('<HHIQQQIHHHHHH', 
    2, # e_type (EXEC)
    62, # e_machine (x86_64)
    1, # e_version
    0x401000, # e_entry (Entry point)
    0x40, # e_phoff
    0, # e_shoff
    0, # e_flags
    64, # e_ehsize
    56, # e_phentsize
    1, # e_phnum
    64, # e_shentsize
    0, # e_shnum
    0 # e_shstrndx
)
elf_data = bytes(elf_header) + b'\x00' * 100

# 2. UTF-16LE metadata file
metadata_text = "Version: 1.2.4\nAuthor: SecOps"
metadata_data = metadata_text.encode('utf-16le')

# 3. Malicious script
malicious_data = b"echo 'You have been hacked'"

files_to_pack = [
    ("bin/app.elf", elf_data),
    ("../../../escape.sh", malicious_data),
    ("metadata.txt", metadata_data)
]

with open('/home/user/artifacts/bundle.bin', 'wb') as f:
    f.write(b'ARTF')
    f.write(struct.pack('<I', len(files_to_pack)))
    for path, data in files_to_pack:
        path_bytes = path.encode('utf-8')
        f.write(struct.pack('<H', len(path_bytes)))
        f.write(path_bytes)
        f.write(struct.pack('<I', len(data)))
        f.write(data)
EOF

    chmod -R 777 /home/user
