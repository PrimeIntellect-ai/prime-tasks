#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile
import zlib
from pathlib import Path

LIB = Path('/app/miniz-3.0.2/libminiz.a')
CPP = Path('/home/user/organizer.cpp')
DATASET = Path('/home/user/dataset')
OUTPUT = Path('/home/user/organized.bin')
EXE = Path('/tmp/organizer_verify')
MINIZ_DIR = Path('/app/miniz-3.0.2')


def decompress_complete(path):
    data = Path(path).read_bytes()
    assert data, 'The output file is empty.'
    errors = []
    for wbits in (zlib.MAX_WBITS, -zlib.MAX_WBITS):
        try:
            obj = zlib.decompressobj(wbits)
            result = obj.decompress(data) + obj.flush()
            assert obj.eof, 'The deflate stream is truncated.'
            assert not obj.unused_data, 'The archive contains trailing data.'
            assert not obj.unconsumed_tail, 'The archive was not fully consumed.'
            assert result, 'Decompressed data is empty.'
            return result
        except (zlib.error, AssertionError) as exc:
            errors.append(str(exc))
    raise AssertionError('Failed to decompress as standard zlib or raw deflate: ' + '; '.join(errors))


def required_payloads(root):
    payloads = []
    timestamp = re.compile(br'^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] ', re.MULTILINE)
    for path in root.iterdir():
        if path.is_file() and path.suffix == '.log':
            payloads.append((path.name, timestamp.sub(b'', path.read_bytes())))
        elif path.is_file() and path.suffix == '.dat':
            payloads.append((path.name, path.read_bytes()[:16]))
    return payloads


def assert_concatenation(actual, root):
    remaining = required_payloads(root)
    position = 0
    while position < len(actual):
        matches = [(i, name, data) for i, (name, data) in enumerate(remaining)
                   if data and actual.startswith(data, position)]
        assert matches, f'Decompressed data at offset {position} is not the required content of any remaining dataset file.'
        # Required file payloads in this task are distinct; prefer the longest if prefixes overlap.
        i, name, data = max(matches, key=lambda item: len(item[2]))
        position += len(data)
        remaining.pop(i)
    assert position == len(actual)
    assert not remaining, 'Missing or empty dataset payloads: ' + ', '.join(name for name, _ in remaining)


def build_reference_helper(tmp):
    source = Path(tmp) / 'miniz_reference.cpp'
    binary = Path(tmp) / 'miniz_reference'
    source.write_text(r'''#include "miniz.h"
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <vector>
int main(int argc, char **argv) {
    if (argc != 4) return 2;
    std::ifstream f(argv[1], std::ios::binary);
    std::vector<unsigned char> input((std::istreambuf_iterator<char>(f)), {});
    mz_ulong output_len = mz_compressBound((mz_ulong)input.size());
    std::vector<unsigned char> output(output_len);
    int status = mz_compress2(output.data(), &output_len, input.data(),
                              (mz_ulong)input.size(), std::atoi(argv[3]));
    if (status != MZ_OK) return 3;
    std::ofstream o(argv[2], std::ios::binary | std::ios::trunc);
    o.write(reinterpret_cast<const char *>(output.data()), output_len);
    return o ? 0 : 4;
}
''')
    subprocess.run(['g++', '-std=c++17', '-O2', '-I', str(MINIZ_DIR), str(source),
                    str(LIB), '-o', str(binary)], check=True, timeout=120)
    return binary


def assert_level9_miniz_stream(helper, decompressed, archive, tmp):
    plain = Path(tmp) / 'plain.bin'
    reference = Path(tmp) / 'level9.bin'
    plain.write_bytes(decompressed)
    subprocess.run([str(helper), str(plain), str(reference), '9'], check=True, timeout=120)
    expected = reference.read_bytes()
    actual = Path(archive).read_bytes()
    # Accept miniz's normal zlib wrapper or the corresponding raw deflate stream.
    assert actual == expected or actual == expected[2:-4], \
        'Archive is not the level-9 miniz deflate stream for the produced content.'


def run_and_check(helper, root, tmp):
    subprocess.run([str(EXE)], cwd='/home/user', check=True, timeout=180)
    assert OUTPUT.is_file(), 'The organizer did not generate /home/user/organized.bin.'
    decompressed = decompress_complete(OUTPUT)
    assert_concatenation(decompressed, root)
    assert_level9_miniz_stream(helper, decompressed, OUTPUT, tmp)


def test_complete_solution():
    # Preserve all original final-state assertions.
    assert LIB.is_file(), f'The static library {LIB} was not found.'
    assert CPP.is_file(), f'The source file {CPP} is missing.'
    assert OUTPUT.is_file(), f'The output file {OUTPUT} was not generated.'
    assert OUTPUT.stat().st_size <= 85000, 'organized.bin is greater than 85000 bytes.'
    decompress_complete(OUTPUT)

    members = subprocess.check_output(['ar', 't', str(LIB)], text=True).strip()
    assert members, 'libminiz.a is not a usable nonempty static archive.'

    source = CPP.read_text(errors='replace')
    uncommented = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
    assert re.search(r'\bMZ_BEST_COMPRESSION\b|\b9\b', uncommented), \
        'organizer.cpp does not configure MZ_BEST_COMPRESSION or level 9.'

    subprocess.run(['g++', '-std=c++17', '-O2', '-I', str(MINIZ_DIR), str(CPP),
                    str(LIB), '-o', str(EXE)], check=True, timeout=120)
    symbols = subprocess.check_output(['nm', '-C', str(EXE)], text=True, errors='replace')
    assert re.search(r'\b(mz_compress2|mz_deflateInit2?|tdefl_compress|tdefl_compress_buffer)\b', symbols), \
        'The organizer executable does not contain the miniz compression implementation.'

    with tempfile.TemporaryDirectory() as tmp:
        helper = build_reference_helper(tmp)
        backup = Path(tmp) / 'original_dataset'
        DATASET.rename(backup)
        try:
            DATASET.mkdir()
            nonce = os.urandom(8).hex()
            for i in range(7):
                lines = []
                for j in range(80 + i * 7):
                    lines.append(f'[2026-09-{i+1:02d} 13:{j%60:02d}:{(j*7)%60:02d}] record-{nonce}-{i}-{j%13}-' + ('ABCD' * (20 + (j % 9))) + '\n')
                (DATASET / f'probe_{i}_{nonce}.log').write_text(''.join(lines))
                header = bytes(((i * 37 + k * 19) % 256 for k in range(16)))
                (DATASET / f'probe_{i}_{nonce}.dat').write_bytes(header + os.urandom(91))
            (DATASET / 'ignored.txt').write_text('must not be included')
            run_and_check(helper, DATASET, tmp)
        finally:
            if DATASET.exists():
                shutil.rmtree(DATASET)
            backup.rename(DATASET)

        # Re-run on the required dataset and verify the final artifact.
        run_and_check(helper, DATASET, tmp)
        assert OUTPUT.stat().st_size <= 85000, 'Final organized.bin is greater than 85000 bytes.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
