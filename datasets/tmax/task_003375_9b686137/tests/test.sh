#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import re
import shutil
import string
import subprocess
import tempfile
from pathlib import Path

PROJECT = Path('/home/user/mobile_telemetry')
MAIN_RS = PROJECT / 'src/main.rs'
C_SOURCE = PROJECT / 'src/legacy_decoder.c'
TELEMETRY = Path('/home/user/telemetry.bin')
OUTPUT = Path('/home/user/parsed_metrics.json')
ENV = os.environ.copy()
ENV.update({
    'RUSTUP_HOME': '/usr/local/rustup',
    'CARGO_HOME': '/usr/local/cargo',
    'PATH': '/usr/local/cargo/bin:' + ENV.get('PATH', ''),
})


def run(cmd, cwd=None, timeout=180):
    result = subprocess.run(cmd, cwd=cwd, env=ENV, capture_output=True, text=True, timeout=timeout)
    assert result.returncode == 0, (
        f"Command failed: {' '.join(map(str, cmd))}\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    return result


def packet(packet_type, payload, valid=True):
    length = len(payload)
    checksum = packet_type ^ length
    for byte in payload:
        checksum ^= byte
    if not valid:
        checksum ^= 1
    return bytes([0xAA, packet_type, length]) + bytes(payload) + bytes([checksum])


def execute_with(raw, expected):
    TELEMETRY.write_bytes(raw)
    if OUTPUT.exists():
        OUTPUT.unlink()
    binary = PROJECT / 'target/debug/mobile_telemetry'
    result = subprocess.run([str(binary)], cwd=PROJECT, env=ENV, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"Program failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert OUTPUT.exists(), 'Program did not create /home/user/parsed_metrics.json'
    try:
        value = json.loads(OUTPUT.read_text())
    except json.JSONDecodeError as exc:
        raise AssertionError(f'Output is not valid JSON: {exc}')
    assert isinstance(value, list), 'Parsed JSON should be an array.'
    assert value == expected, f'Unexpected parser output. Expected {expected!r}, got {value!r}'


def extract_function(text, signature):
    start = text.find(signature)
    assert start >= 0, f'Missing function containing {signature!r}'
    brace = text.find('{', start)
    assert brace >= 0, f'Malformed function containing {signature!r}'
    depth = 0
    for pos in range(brace, len(text)):
        if text[pos] == '{':
            depth += 1
        elif text[pos] == '}':
            depth -= 1
            if depth == 0:
                return text[start:pos + 1]
    raise AssertionError(f'Unterminated function containing {signature!r}')


def test_sources_and_c_decoder():
    assert C_SOURCE.exists(), f'Missing C file: {C_SOURCE}'
    assert MAIN_RS.exists(), f'Missing Rust main file: {MAIN_RS}'

    c_content = C_SOURCE.read_text()

    # Preserve the original source assertion.
    has_bounds_check = ('in_len' in c_content) and (
        '3' in c_content and ('<' in c_content or '>' in c_content or '==' in c_content)
    )
    assert has_bounds_check, 'The C code does not appear to have a bounds check for the 0xFF skip marker.'

    # Verify that the check is in decode_stream's 0xFF path and stops before the skip.
    clean = re.sub(r'/\*.*?\*/|//[^\n]*', '', c_content, flags=re.S)
    body = extract_function(clean, 'decode_stream')
    marker = re.search(r'if\s*\([^)]*(?:0xFF|255)[^)]*\)', body, flags=re.I)
    assert marker, 'decode_stream has no 0xFF skip-marker branch.'
    tail = body[marker.end():]
    advance = re.search(r'in_idx\s*\+=\s*3|in_idx\s*=\s*in_idx\s*\+\s*3', tail)
    assert advance, 'The 0xFF branch does not perform the required three-byte skip.'
    before_advance = tail[:advance.start()]
    guards = list(re.finditer(r'if\s*\(([^)]*)\)', before_advance, flags=re.S))
    guarded_stop = False
    for guard in guards:
        condition = guard.group(1)
        following = before_advance[guard.end():]
        if ('in_len' in condition and 'in_idx' in condition and
                re.search(r'[<>]=?|==', condition) and
                ('3' in condition or re.search(r'in_len\s*-\s*in_idx', condition)) and
                re.search(r'\b(?:return|break)\b', following)):
            guarded_stop = True
            break
    assert guarded_stop, 'The 0xFF path must stop before advancing when fewer than three bytes remain.'

    with tempfile.TemporaryDirectory() as td:
        lib = Path(td) / 'decoder.so'
        run(['gcc', '-shared', '-fPIC', '-O2', str(C_SOURCE), '-o', str(lib)])
        decoder = ctypes.CDLL(str(lib)).decode_stream
        decoder.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t,
                            ctypes.POINTER(ctypes.c_uint8)]
        decoder.restype = ctypes.c_size_t

        def decode(data):
            in_buf = (ctypes.c_uint8 * max(1, len(data)))(*data)
            out_buf = (ctypes.c_uint8 * max(1, len(data)))()
            size = decoder(in_buf, len(data), out_buf)
            assert size <= len(data), 'decode_stream returned an impossible output length.'
            return bytes(out_buf[:size])

        assert decode(bytes([7, 0xFF])) == bytes([7])
        assert decode(bytes([7, 0xFF, 9])) == bytes([7])
        assert decode(bytes([1, 0xFF, 2, 3, 4])) == bytes([1, 4])

    rust_content = MAIN_RS.read_text()
    # Preserve the original architecture assertions.
    assert 'get_pipeline_arch' in rust_content, 'Missing get_pipeline_arch function in main.rs'
    assert 'aarch64' in rust_content, "Function does not seem to return 'aarch64'"
    assert 'x86_64' in rust_content, "Function does not seem to return 'x86_64'"
    assert 'cfg' in rust_content and 'target_arch' in rust_content, 'Missing conditional compilation logic for target architecture.'
    assert re.search(r'pub\s+fn\s+get_pipeline_arch\s*\(', rust_content), 'get_pipeline_arch must be public.'


def test_build_parser_and_fixed_fixture():
    run(['cargo', 'build'], cwd=PROJECT)

    rng = random.SystemRandom()
    while True:
        battery1 = rng.randrange(1000, 10_000_000)
        battery2 = rng.randrange(1000, 10_000_000)
        name = ''.join(rng.choice(string.ascii_letters) for _ in range(11))
        good1 = packet(1, battery1.to_bytes(4, 'big'))
        good2 = packet(2, name.encode())
        good3 = packet(1, battery2.to_bytes(4, 'big'))
        candidates = good1 + good2 + good3
        if 0xFF not in candidates:
            break

    bad_checksum = packet(2, b'REJECT', valid=False)
    unknown_type = packet(9, b'abc')
    wrong_battery_length = packet(1, b'\x00\x01\x02')
    invalid_utf8 = packet(2, b'\xfe\xfe')
    raw = (
        b'\x10\x20\x30' + good1 + b'\xff\x91\x92' + bad_checksum +
        good2 + unknown_type + wrong_battery_length + invalid_utf8 + good3
    )
    expected = [
        {'type': 'battery', 'value': battery1},
        {'type': 'device', 'value': name},
        {'type': 'battery', 'value': battery2},
    ]
    execute_with(raw, expected)

    # Both malformed trailing-marker forms must stop safely after prior output.
    execute_with(good1 + b'\xff', [{'type': 'battery', 'value': battery1}])
    execute_with(good2 + b'\xff\x12', [{'type': 'device', 'value': name}])

    # Truncated packets and streams containing no header produce no fabricated metrics.
    execute_with(b'noise' + bytes([0xAA, 2, 8]) + b'cut', [])

    # Restore and actually execute the supplied fixture, preserving the original exact check.
    original = (
        bytes([0xAA, 1, 4, 0, 0, 0, 42, 47]) +
        bytes([0xFF, 0x00, 0x00]) +
        bytes([0xAA, 2, 5, 80, 73, 88, 69, 76, 113]) +
        bytes([0xFF, 0x12])
    )
    fixed_expected = [
        {'type': 'battery', 'value': 42},
        {'type': 'device', 'value': 'PIXEL'},
    ]
    execute_with(original, fixed_expected)
    data = json.loads(OUTPUT.read_text())
    assert len(data) == 2, f'Expected 2 parsed metrics, got {len(data)}.'
    assert data == fixed_expected, f'JSON content does not match expected valid packets. Got: {data}'


def test_architecture_function_and_cross_build():
    # Preserve the original full-project cross-compilation check.
    run(['cargo', 'build', '--target', 'aarch64-unknown-linux-gnu'], cwd=PROJECT, timeout=300)

    # Exercise the function natively and compile an observable call to it for aarch64.
    with tempfile.TemporaryDirectory() as td:
        copied = Path(td) / 'project'
        shutil.copytree(PROJECT, copied, ignore=shutil.ignore_patterns('target'))
        source = copied / 'src/main.rs'
        with source.open('a') as f:
            f.write(r'''

#[cfg(test)]
mod __verifier_arch_tests {
    #[test]
    fn reports_native_architecture() {
        assert_eq!(super::get_pipeline_arch(), "x86_64");
    }
}

#[no_mangle]
pub extern "C" fn __verifier_arch_result_91f3() -> u8 {
    match get_pipeline_arch() {
        "aarch64" => 1,
        "x86_64" => 2,
        _ => 0,
    }
}
''')
        run(['cargo', 'test', '--quiet'], cwd=copied, timeout=300)
        run(['cargo', 'rustc', '--release', '--target', 'aarch64-unknown-linux-gnu',
             '--', '--emit=llvm-ir'], cwd=copied, timeout=300)
        llvm_files = list((copied / 'target/aarch64-unknown-linux-gnu/release/deps').glob('mobile_telemetry-*.ll'))
        assert llvm_files, 'Cross-compilation did not emit LLVM IR for the telemetry program.'
        llvm = '\n'.join(path.read_text(errors='replace') for path in llvm_files)
        match = re.search(r'define[^@]*@__verifier_arch_result_91f3\([^)]*\)[^{]*\{(.*?)^\}',
                          llvm, flags=re.S | re.M)
        assert match, 'Could not inspect get_pipeline_arch in the aarch64 build.'
        assert re.search(r'\bret\s+i8(?:\s+noundef)?\s+1\b', match.group(1)), (
            'get_pipeline_arch does not return "aarch64" in the aarch64 build.'
        )


def main():
    assert PROJECT.exists(), f'Missing project directory: {PROJECT}'
    test_sources_and_c_decoder()
    test_build_parser_and_fixed_fixture()
    test_architecture_function_and_cross_build()


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
