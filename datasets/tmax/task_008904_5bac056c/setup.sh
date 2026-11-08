#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest chardet

    useradd -m -s /bin/bash user || true

    python3 << 'EOF'
import os
import struct

os.makedirs('/home/user/artifact_staging/bin', exist_ok=True)
os.makedirs('/home/user/artifact_staging/docs', exist_ok=True)
os.makedirs('/home/user/artifact_staging/hardware', exist_ok=True)

# 1. Create a dummy x86_64 ELF file
# e_machine for x86_64 is 0x3E (62)
elf_x86 = bytearray(b'\x7fELF\x02\x01\x01\x00' + b'\x00'*8) # e_ident
elf_x86 += struct.pack('<H', 2) # e_type (EXEC)
elf_x86 += struct.pack('<H', 0x3E) # e_machine (x86_64)
elf_x86 += b'\x00' * 40 # padding to make it pass basic checks
with open('/home/user/artifact_staging/bin/app_x86', 'wb') as f:
    f.write(elf_x86)

# 2. Create a dummy ARM ELF file
# e_machine for ARM is 0x28 (40)
elf_arm = bytearray(b'\x7fELF\x01\x01\x01\x00' + b'\x00'*8)
elf_arm += struct.pack('<H', 2) # e_type
elf_arm += struct.pack('<H', 0x28) # e_machine (ARM)
elf_arm += b'\x00' * 40
with open('/home/user/artifact_staging/bin/app_arm', 'wb') as f:
    f.write(elf_arm)

# 3. Create a UTF-16LE encoded .txt file
text_content = "Release Notes: v1.0.0\nFixed: Buffer overflow in parser.\n"
with open('/home/user/artifact_staging/docs/release_notes.txt', 'wb') as f:
    f.write(text_content.encode('utf-16le'))

# 4. Create an ISO-8859-1 encoded .gcode file
gcode_content = "; GCode Header\n; Temperature: 210°C\nG28\nG1 X10 Y10\n"
with open('/home/user/artifact_staging/hardware/case_print.gcode', 'wb') as f:
    f.write(gcode_content.encode('iso-8859-1'))
EOF

    chmod -R 777 /home/user
