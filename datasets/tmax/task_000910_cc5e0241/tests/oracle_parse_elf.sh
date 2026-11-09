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
