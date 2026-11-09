#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import ctypes
import os
import random
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path('/home/user/sysproj')
SO = ROOT / 'libring.so'
PY_SUITE = ROOT / 'test_suite.py'
LOG = ROOT / 'test_results.log'
PATCH = ROOT / 'fix.patch'
MAKEFILE = ROOT / 'Makefile'
SOURCE = ROOT / 'libring.c'
ORIG_MAKEFILE = ROOT / 'Makefile.orig'
ORIG_SOURCE = ROOT / 'libring.c.orig'


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


def apply_unified_section(original, hunk_lines):
    old = original.splitlines(keepends=True)
    out = []
    old_pos = 0
    i = 0
    while i < len(hunk_lines):
        line = hunk_lines[i]
        if not line.startswith('@@ '):
            i += 1
            continue
        match = re.match(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@', line)
        assert match, f'Invalid unified-diff hunk header: {line!r}'
        start = int(match.group(1))
        target = start - 1
        assert target >= old_pos, 'Overlapping or out-of-order patch hunks.'
        out.extend(old[old_pos:target])
        old_pos = target
        i += 1
        while i < len(hunk_lines) and not hunk_lines[i].startswith('@@ ') and not hunk_lines[i].startswith('--- '):
            item = hunk_lines[i]
            if item.startswith('\\ No newline at end of file'):
                i += 1
                continue
            assert item and item[0] in ' +-', f'Invalid unified-diff line: {item!r}'
            payload = item[1:]
            if item[0] == ' ':
                assert old_pos < len(old) and old[old_pos] == payload, 'Patch context does not match the original file.'
                out.append(payload)
                old_pos += 1
            elif item[0] == '-':
                assert old_pos < len(old) and old[old_pos] == payload, 'Patch deletion does not match the original file.'
                old_pos += 1
            else:
                out.append(payload)
            i += 1
    out.extend(old[old_pos:])
    return ''.join(out)


def verify_patch_reconstructs_files():
    text = PATCH.read_text()
    assert 'Makefile' in text, 'Patch does not contain changes for Makefile.'
    assert 'libring.c' in text, 'Patch does not contain changes for libring.c.'
    assert '-fPIC' in text or '-fpic' in text, 'Patch does not show the addition of -fPIC to Makefile.'
    assert 'DEBUG_MODE' in text, 'Patch does not show the usage of DEBUG_MODE in libring.c.'
    assert 'RingBuffer Dump' in text, 'Patch does not show the print statement in libring.c.'

    lines = text.splitlines(keepends=True)
    reconstructed = {}
    i = 0
    while i < len(lines):
        if not lines[i].startswith('--- '):
            i += 1
            continue
        assert i + 1 < len(lines) and lines[i + 1].startswith('+++ '), 'Malformed unified diff headers.'
        old_name = lines[i][4:].rstrip('\n').split('\t', 1)[0]
        new_name = lines[i + 1][4:].rstrip('\n').split('\t', 1)[0]
        i += 2
        body_start = i
        while i < len(lines) and not lines[i].startswith('--- '):
            i += 1
        body = lines[body_start:i]
        names = {Path(old_name).name, Path(new_name).name}
        if 'libring.c' in names or 'libring.c.orig' in names:
            reconstructed['libring.c'] = apply_unified_section(ORIG_SOURCE.read_text(), body)
        elif 'Makefile' in names or 'Makefile.orig' in names:
            reconstructed['Makefile'] = apply_unified_section(ORIG_MAKEFILE.read_text(), body)

    assert reconstructed.get('libring.c') == SOURCE.read_text(), 'fix.patch does not reproduce the submitted libring.c from its original.'
    assert reconstructed.get('Makefile') == MAKEFILE.read_text(), 'fix.patch does not reproduce the submitted Makefile from its original.'


def main():
    # Preserve the original existence/content assertions.
    assert MAKEFILE.is_file(), f'{MAKEFILE} does not exist.'
    assert SOURCE.is_file(), f'{SOURCE} does not exist.'
    assert ORIG_MAKEFILE.is_file() and ORIG_SOURCE.is_file(), 'Original files needed for the requested diff are missing.'
    assert PY_SUITE.is_file(), f'{PY_SUITE} does not exist.'
    py_content = PY_SUITE.read_text()
    assert 'ctypes' in py_content, f'{PY_SUITE} does not import or use ctypes.'
    for name in ('rb_init', 'rb_push', 'rb_pop', 'rb_dump'):
        assert name in py_content, f'{PY_SUITE} does not call {name}.'
    assert PATCH.is_file(), f'{PATCH} does not exist.'
    verify_patch_reconstructs_files()

    # Exercise the submitted Makefile and require it to produce a loadable shared object.
    run(['make', 'clean'], cwd=ROOT)
    run(['make', 'all'], cwd=ROOT)
    assert SO.is_file(), f'{SO} does not exist after make all.'
    assert SO.read_bytes()[:4] == b'\x7fELF', f'{SO} is not a valid ELF file.'
    elf = run(['readelf', '-h', str(SO)], text=True).stdout
    assert re.search(r'Type:\s+DYN', elf), 'libring.so is not an ELF shared object.'
    ctypes.CDLL(str(SO))

    # Test real ring-buffer behavior using values chosen by the verifier, and verify
    # that the Makefile-built library has DEBUG_MODE behavior enabled.
    a = random.randint(100000, 900000)
    b = random.randint(100000, 900000)
    helper = f'''import ctypes\nlib=ctypes.CDLL({str(SO)!r})\nlib.rb_push.argtypes=[ctypes.c_int]\nlib.rb_pop.restype=ctypes.c_int\nlib.rb_init()\nlib.rb_push({a})\nlib.rb_push({b})\nx=lib.rb_pop()\ny=lib.rb_pop()\nlib.rb_dump()\nctypes.CDLL(None).fflush(None)\nprint("VALUES:%d,%d" % (x,y), flush=True)\n'''
    actual = run(['python3', '-c', helper], text=True).stdout
    assert f'VALUES:{a},{b}' in actual, 'The built library does not implement the required init/push/pop behavior.'
    assert 'RingBuffer Dump' in actual, 'The Makefile-built library was not built with working DEBUG_MODE rb_dump output.'

    # Compile the same submitted C source without DEBUG_MODE and ensure rb_dump is
    # a real exported empty stub rather than unconditional output.
    with tempfile.TemporaryDirectory() as td:
        nodebug = Path(td) / 'libring_nodebug.so'
        run(['gcc', '-Wall', '-fPIC', '-shared', '-I', str(ROOT), str(SOURCE), '-o', str(nodebug)])
        quiet_helper = f'''import ctypes\nlib=ctypes.CDLL({str(nodebug)!r})\nlib.rb_dump()\nctypes.CDLL(None).fflush(None)\n'''
        quiet = run(['python3', '-c', quiet_helper])
        assert quiet.stdout == b'', 'rb_dump must produce no stdout when DEBUG_MODE is not defined.'

    # Execute the submitted Python suite against the actual library and require the
    # saved log to be exactly its standard output.
    assert LOG.is_file(), f'{LOG} does not exist.'
    suite_run = run(['python3', str(PY_SUITE)], cwd=ROOT)
    assert suite_run.stdout == LOG.read_bytes(), 'test_results.log is not the standard output of the submitted Python test suite.'
    log_content = LOG.read_text()
    assert '10' in log_content, f'{LOG} does not contain the popped value 10.'
    assert 'RingBuffer Dump' in log_content, f"{LOG} does not contain 'RingBuffer Dump'."

    # Replace the library temporarily with an instrumented ABI-compatible probe.
    # This proves the Python program really loads it, pushes 10 then 20, pops and
    # prints the returned value, and finally calls rb_dump.
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        backup = td / 'real_libring.so'
        shutil.copy2(SO, backup)
        trace = td / 'calls.log'
        returned = random.randint(1200000, 1900000)
        probe_c = td / 'probe.c'
        probe_so = td / 'probe.so'
        probe_c.write_text(f'''#include <stdio.h>\nstatic void logline(const char *s) {{ FILE *f=fopen("{trace}", "a"); if (f) {{ fputs(s,f); fclose(f); }} }}\nvoid rb_init(void) {{ FILE *f=fopen("{trace}", "w"); if(f) {{ fputs("I\\n",f); fclose(f); }} }}\nvoid rb_push(int v) {{ FILE *f=fopen("{trace}", "a"); if(f) {{ fprintf(f,"P%d\\n",v); fclose(f); }} }}\nint rb_pop(void) {{ logline("O\\n"); return {returned}; }}\nvoid rb_dump(void) {{ logline("D\\n"); puts("RingBuffer Dump"); fflush(stdout); }}\n''')
        run(['gcc', '-fPIC', '-shared', str(probe_c), '-o', str(probe_so)])
        try:
            shutil.copy2(probe_so, SO)
            probed = run(['python3', str(PY_SUITE)], cwd=ROOT, text=True)
        finally:
            shutil.copy2(backup, SO)
        assert trace.is_file(), 'The Python suite did not load and call the probe library.'
        assert trace.read_text().splitlines() == ['I', 'P10', 'P20', 'O', 'D'], 'The Python suite did not perform rb_init, pushes of 10 and 20, rb_pop, and rb_dump in order.'
        assert str(returned) in probed.stdout, 'The Python suite did not print the value actually returned by rb_pop.'


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
