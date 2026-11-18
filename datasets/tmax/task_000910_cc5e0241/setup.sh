#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils file gcc gcc-aarch64-linux-gnu libc6-dev
    pip3 install pytest Pillow

    # Create policy image
    mkdir -p /app
    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
text = """ELF Binary Admission Policy
Evaluate files in this exact order:
1. If not an ELF file -> INVALID: Not ELF
2. If machine architecture is not Advanced Micro Devices X86-64 -> INVALID: Not x86-64
3. If type is not EXEC (Executable file) or DYN (Shared object file) -> INVALID: Not DYN/EXEC
4. If it does not contain a section named exactly '.rodata' -> INVALID: No .rodata

If all checks pass, output -> VALID: <Entry point address>
(Format the entry point exactly as readelf outputs it, e.g., 0x401000 or 0x0)"""
img = Image.new('RGB', (800, 400), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/policy.png')
EOF
    python3 /tmp/make_image.py
    rm /tmp/make_image.py

    # Create oracle script
    mkdir -p /test
    cat << 'EOF' > /test/oracle_parse_elf.sh
#!/bin/bash
FILE=$1

if ! readelf -h "$FILE" >/dev/null 2>&1; then
    echo "INVALID: Not ELF"
    exit 0
fi

ARCH=$(readelf -h "$FILE" | grep "Machine:" | sed 's/.*Machine:[[:space:]]*//')
if [[ "$ARCH" != *"Advanced Micro Devices X86-64"* ]]; then
    echo "INVALID: Not x86-64"
    exit 0
fi

TYPE=$(readelf -h "$FILE" | grep "Type:" | sed 's/.*Type:[[:space:]]*//')
if [[ "$TYPE" != *"EXEC (Executable file)"* ]] && [[ "$TYPE" != *"DYN (Shared object file)"* ]] && [[ "$TYPE" != *"DYN (Position-Independent Executable file)"* ]]; then
    if [[ "$TYPE" != *"EXEC"* ]] && [[ "$TYPE" != *"DYN"* ]]; then
        echo "INVALID: Not DYN/EXEC"
        exit 0
    fi
fi

if ! readelf -S "$FILE" 2>/dev/null | grep -q " \.rodata "; then
    echo "INVALID: No .rodata"
    exit 0
fi

ENTRY=$(readelf -h "$FILE" | grep "Entry point address:" | awk '{print $NF}')
echo "VALID: $ENTRY"
EOF
    chmod +x /test/oracle_parse_elf.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
