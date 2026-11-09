#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import os
import random
import re
import shutil
import subprocess
import uuid
from pathlib import Path

HOME = Path('/home/user')
CONFIGS = HOME / 'configs'
TSV = HOME / 'valid_changes.tsv'
CPP = HOME / 'tracker.cpp'
PIPELINE = HOME / 'run_pipeline.sh'
TOKEN = uuid.uuid4().hex[:12]


def clear_configs():
    CONFIGS.mkdir(parents=True, exist_ok=True)
    for path in CONFIGS.iterdir():
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
        else:
            path.unlink()


def write_config(name, data):
    path = CONFIGS / name
    if isinstance(data, str):
        data = data.encode('utf-8')
    path.write_bytes(data)
    return path


def remove_output():
    if TSV.exists() or TSV.is_symlink():
        TSV.unlink()


def run(command, timeout=40):
    result = subprocess.run(
        command,
        cwd=str(HOME),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        text=True,
    )
    assert result.returncode == 0, (
        f"Command failed: {command}\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    return result


def read_output():
    assert TSV.is_file(), f"{TSV} does not exist."
    with TSV.open('r', encoding='utf-8') as stream:
        return [line.strip('\n') for line in stream if line.strip('\n')]


def assert_output(expected):
    actual = read_output()
    assert actual == expected, (
        f"Content of {TSV} does not match the expected output.\n"
        f"Expected:\n{expected}\nActual:\n{actual}"
    )


# Preserve and exercise the original fixed-fixture assertion, but do not trust a
# pre-created TSV: the submitted pipeline must regenerate it.
clear_configs()
write_config('a_init.conf', 'SERVER_PORT=8080\nDB_HOST=localhost\nWELCOME_MSG=Hello World\n')
write_config('b_update.conf', 'SERVER_PORT=9000\nMAX_CONN=100\nGREETING=¡Hola Mundo!\n')
write_config('c_invalid.conf', 'INVALID-KEY=123\nDB_HOST=remote\n')
write_config('d_override.conf', 'MAX_CONN=500\nDB_PASS=S3cr3t\n')
write_config('e_bad_value.conf', 'NEW_KEY=ValidValue\nBAD_VALUE=Has\nNewline\n')

assert PIPELINE.is_file(), f"{PIPELINE} does not exist."
assert CPP.is_file(), f"{CPP} does not exist."
remove_output()
run(['bash', str(PIPELINE)])
assert_output([
    'DB_HOST\tlocalhost\ta_init.conf',
    'DB_PASS\tS3cr3t\td_override.conf',
    'GREETING\t¡Hola Mundo!\tb_update.conf',
    'MAX_CONN\t500\td_override.conf',
    'SERVER_PORT\t9000\tb_update.conf',
    'WELCOME_MSG\tHello World\ta_init.conf',
])

# Retain the original concurrency assertion and additionally ensure the token is
# actual source code rather than text placed only in a comment or string.
source = CPP.read_text(encoding='utf-8')
concurrency_keywords = ['std::thread', 'async', 'execution::par', 'pthread']
assert any(keyword in source for keyword in concurrency_keywords), (
    'tracker.cpp does not appear to use std::thread, std::async, '
    'or C++17 parallel algorithms (execution::par) as required.'
)
code_only = re.sub(
    r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'',
    ' ',
    source,
    flags=re.DOTALL,
)
assert re.search(r'\bstd\s*::\s*(?:thread|async)\b|\bstd\s*::\s*execution\s*::\s*par\b|\bpthread_[A-Za-z0-9_]+\b', code_only), (
    'The concurrency keyword appears only in a comment/string, or no supported '
    'concurrency facility is used in tracker.cpp.'
)

# Compile tracker.cpp independently and exercise it on unpredictable changed
# inputs, including whole-file rejection, byte limits, controls, UTF-8, sorting,
# and basename-based overrides.
clear_configs()
a_name = f'a_{TOKEN}.conf'
z_name = f'z_{TOKEN}.conf'
paths = [
    write_config(a_name,
        ('SHARED=from_low_' + TOKEN + '\n'
         'ALPHA=first_' + TOKEN + '\n'
         'KEY_' + ('Q' * 28) + '=key32\n'
         'VALUE256=' + ('x' * 256) + '\n'
         'SPACED=hello world\n').encode('utf-8')),
    write_config(z_name,
        ('SHARED=from_high_' + TOKEN + '\n'
         'UNICODE=雪と¡Hola!_' + TOKEN + '\n'
         'ZED=last\n').encode('utf-8')),
    write_config(f'invalid_key_{TOKEN}.conf', b'GOOD=must_not_appear\nBAD-KEY=no\n'),
    write_config(f'missing_equal_{TOKEN}.conf', b'OTHER=must_not_appear\nnot-a-pair\n'),
    write_config(f'empty_value_{TOKEN}.conf', b'EMPTY=\nHIDDEN=no\n'),
    write_config(f'long_key_{TOKEN}.conf', (('K' * 33) + '=bad\nHIDDEN2=no\n').encode()),
    write_config(f'long_value_{TOKEN}.conf', (b'TOO_LONG=' + b'y' * 257 + b'\nHIDDEN3=no\n')),
    write_config(f'tab_control_{TOKEN}.conf', b'TAB=bad\tvalue\nHIDDEN4=no\n'),
    write_config(f'nul_control_{TOKEN}.conf', b'NUL=bad\x00value\nHIDDEN5=no\n'),
    write_config(f'cr_control_{TOKEN}.conf', b'CR=bad\r\nHIDDEN6=no\n'),
]
random.SystemRandom().shuffle(paths)
verifier_binary = Path('/tmp') / f'tracker_verify_{TOKEN}'
run(['g++', '-std=c++17', '-pthread', '-O2', str(CPP), '-o', str(verifier_binary)])
remove_output()
run([str(verifier_binary)] + [str(path) for path in paths])
assert_output(sorted([
    f'ALPHA\tfirst_{TOKEN}\t{a_name}',
    f'KEY_{"Q" * 28}\tkey32\t{a_name}',
    f'SHARED\tfrom_high_{TOKEN}\t{z_name}',
    f'SPACED\thello world\t{a_name}',
    f'UNICODE\t雪と¡Hola!_{TOKEN}\t{z_name}',
    f'VALUE256\t{"x" * 256}\t{a_name}',
    f'ZED\tlast\t{z_name}',
]))

# Change the fixture again and verify that run_pipeline.sh recompiles this exact
# source and executes the resulting program. A harmless injected global
# constructor leaves a marker only when the newly compiled tracker is run.
clear_configs()
low_name = f'b_pipe_{TOKEN}.conf'
high_name = f'y_pipe_{TOKEN}.conf'
write_config(low_name, f'PIPE_ONLY=low_{TOKEN}\nDUP=old_{TOKEN}\n')
write_config(high_name, f'DUP=new_{TOKEN}\nFINAL=ok_{TOKEN}\n')
write_config(f'm_invalid_{TOKEN}.conf', f'SHOULD_NOT_SHOW=x\nbad_key=y\n')
write_config(f'ignored_{TOKEN}.txt', f'NOT_CONF=bad_{TOKEN}\n')

marker = Path('/tmp') / f'tracker_ran_{TOKEN}'
identifier = f'VerifierMarker_{TOKEN}'
injected = (
    '#include <fstream>\n'
    f'struct {identifier} {{ {identifier}() {{ '
    f'std::ofstream("{marker}") << "ran"; }} }} {identifier}_instance;\n'
)
CPP.write_text(injected + source, encoding='utf-8')
if marker.exists():
    marker.unlink()
remove_output()
run(['bash', str(PIPELINE)])
assert marker.is_file(), (
    'run_pipeline.sh did not compile and execute the submitted tracker.cpp.'
)
assert_output(sorted([
    f'DUP\tnew_{TOKEN}\t{high_name}',
    f'FINAL\tok_{TOKEN}\t{high_name}',
    f'PIPE_ONLY\tlow_{TOKEN}\t{low_name}',
]))
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
