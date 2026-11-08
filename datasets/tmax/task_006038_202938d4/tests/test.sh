#!/bin/bash
set -e
mkdir -p /logs/verifier

NASM_PATH=/usr/bin/nasm
LD_PATH=/usr/bin/ld
NASM_BACKUP=/tmp/verifier_nasm_original
LD_BACKUP=/tmp/verifier_ld_original
NASM_TARGET=$(readlink -f "$NASM_PATH")
LD_TARGET=$(readlink -f "$LD_PATH")

mv "$NASM_PATH" "$NASM_BACKUP"
mv "$LD_PATH" "$LD_BACKUP"
if [ "$NASM_TARGET" = "$NASM_PATH" ]; then NASM_EXEC="$NASM_BACKUP"; else NASM_EXEC="$NASM_TARGET"; fi
if [ "$LD_TARGET" = "$LD_PATH" ]; then LD_EXEC="$LD_BACKUP"; else LD_EXEC="$LD_TARGET"; fi

cat > "$NASM_PATH" <<EOF
#!/bin/bash
echo nasm >> /tmp/verifier_tool_invocations
exec "$NASM_EXEC" "\$@"
EOF
cat > "$LD_PATH" <<EOF
#!/bin/bash
echo ld >> /tmp/verifier_tool_invocations
exec "$LD_EXEC" "\$@"
EOF
chmod 755 "$NASM_PATH" "$LD_PATH"

restore_tools() {
    rm -f "$NASM_PATH" "$LD_PATH"
    mv "$NASM_BACKUP" "$NASM_PATH"
    mv "$LD_BACKUP" "$LD_PATH"
}
trap restore_tools EXIT

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import json
import math
import os
import random
import re
import secrets
import stat
import subprocess
import zlib

RESOLVE_PATH = '/home/user/resolve.py'
PACKAGES_PATH = '/home/user/packages'
RESOLVED_LIST_PATH = '/home/user/resolved_list.txt'
EXIT_ASM_PATH = '/home/user/exit.asm'
COUNT_BIN_PATH = '/home/user/count_bin'
BENCHMARK_LOG_PATH = '/home/user/benchmark.log'
TOOL_LOG = '/tmp/verifier_tool_invocations'


def write_packages(packages):
    os.makedirs(PACKAGES_PATH, exist_ok=True)
    for entry in os.listdir(PACKAGES_PATH):
        path = os.path.join(PACKAGES_PATH, entry)
        if os.path.isfile(path) or os.path.islink(path):
            os.unlink(path)
    random.SystemRandom().shuffle(packages)
    for index, package in enumerate(packages):
        raw = json.dumps(package).encode('utf-8')
        encoded = base64.b64encode(zlib.compress(raw)).decode('ascii')
        with open(os.path.join(PACKAGES_PATH, f'input_{index}_{secrets.token_hex(3)}.dat'), 'w') as handle:
            handle.write(encoded)


def clear_outputs():
    for path in (RESOLVED_LIST_PATH, EXIT_ASM_PATH, COUNT_BIN_PATH, BENCHMARK_LOG_PATH, TOOL_LOG):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def run_submission():
    result = subprocess.run(['python3', RESOLVE_PATH], cwd='/home/user', text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    assert result.returncode == 0, f'resolve.py failed:\nstdout={result.stdout}\nstderr={result.stderr}'


def assert_source_and_timeit():
    assert os.path.exists(RESOLVE_PATH), f'File {RESOLVE_PATH} is missing.'
    assert os.path.isfile(RESOLVE_PATH), f'{RESOLVE_PATH} is not a file.'
    with open(RESOLVE_PATH, 'r', encoding='utf-8') as handle:
        source = handle.read()
    tree = ast.parse(source, filename=RESOLVE_PATH)
    imported_timeit = any(
        (isinstance(node, ast.Import) and any(alias.name == 'timeit' for alias in node.names)) or
        (isinstance(node, ast.ImportFrom) and node.module == 'timeit')
        for node in ast.walk(tree)
    )
    assert imported_timeit, 'resolve.py must use Python timeit.'
    exact_call = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        name = node.func.attr if isinstance(node.func, ast.Attribute) else (node.func.id if isinstance(node.func, ast.Name) else '')
        if name not in ('timeit', 'repeat'):
            continue
        values = list(node.args) + [keyword.value for keyword in node.keywords if keyword.arg == 'number']
        if any(isinstance(value, ast.Constant) and value.value == 1000 for value in values):
            exact_call = True
    assert exact_call, 'The timeit benchmark must specify exactly 1000 executions.'
    functions = [node for node in tree.body if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))]
    assert functions, 'Graph resolution logic must be encapsulated in a function.'


def validate_outputs(expected_lines, expected_count):
    assert os.path.exists(RESOLVED_LIST_PATH), f'File {RESOLVED_LIST_PATH} is missing.'
    assert os.path.isfile(RESOLVED_LIST_PATH), f'{RESOLVED_LIST_PATH} is not a file.'
    with open(RESOLVED_LIST_PATH, 'r', encoding='utf-8') as handle:
        content = handle.read().strip()
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert actual_lines == expected_lines, 'Resolved packages are incorrect or not alphabetically sorted.'

    assert os.path.exists(EXIT_ASM_PATH), f'Assembly file {EXIT_ASM_PATH} is missing.'
    assert os.path.isfile(EXIT_ASM_PATH), f'{EXIT_ASM_PATH} is not a file.'
    assert os.path.getsize(EXIT_ASM_PATH) > 0, f'{EXIT_ASM_PATH} is empty.'

    assert os.path.exists(COUNT_BIN_PATH), f'Executable {COUNT_BIN_PATH} is missing.'
    assert os.path.isfile(COUNT_BIN_PATH), f'{COUNT_BIN_PATH} is not a file.'
    assert os.access(COUNT_BIN_PATH, os.X_OK), f'{COUNT_BIN_PATH} is not executable.'
    with open(COUNT_BIN_PATH, 'rb') as handle:
        header = handle.read(20)
    assert header[:4] == b'\x7fELF', 'count_bin is not an ELF executable.'
    assert len(header) >= 20 and header[4] == 2 and int.from_bytes(header[18:20], 'little') == 62, 'count_bin is not x86_64 ELF.'
    result = subprocess.run([COUNT_BIN_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    assert result.returncode == expected_count, f'Expected exit code {expected_count}, got {result.returncode}.'

    assert os.path.exists(BENCHMARK_LOG_PATH), f'File {BENCHMARK_LOG_PATH} is missing.'
    assert os.path.isfile(BENCHMARK_LOG_PATH), f'{BENCHMARK_LOG_PATH} is not a file.'
    with open(BENCHMARK_LOG_PATH, 'r', encoding='utf-8') as handle:
        lines = [line.strip() for line in handle if line.strip()]
    assert len(lines) == 1, 'A fresh run must append exactly one benchmark result.'
    match = re.fullmatch(r'Benchmark:\s*([0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)', lines[0])
    assert match, 'Benchmark must contain a numeric total duration.'
    duration = float(match.group(1))
    assert math.isfinite(duration) and duration >= 0, 'Benchmark duration must be a finite nonnegative number.'

    with open(TOOL_LOG, 'r', encoding='utf-8') as handle:
        tools = handle.read().splitlines()
    assert 'nasm' in tools, 'resolve.py did not invoke nasm.'
    assert 'ld' in tools, 'resolve.py did not invoke ld.'


def test_submission_on_original_and_unseen_data():
    assert_source_and_timeit()

    original = [
        {'name': 'root', 'version': '1.0.0', 'dependencies': {'A': '>=1.0.0'}},
        {'name': 'A', 'version': '1.0.0', 'dependencies': {'B': '>=1.0.0'}},
        {'name': 'A', 'version': '1.5.0', 'dependencies': {'B': '>=2.0.0'}},
        {'name': 'B', 'version': '1.0.0', 'dependencies': {'C': '>=1.0.0'}},
        {'name': 'B', 'version': '2.5.0', 'dependencies': {'C': '>=1.0.0'}},
        {'name': 'C', 'version': '1.1.0', 'dependencies': {'A': '>=1.0.0'}},
        {'name': 'D', 'version': '2.0.0', 'dependencies': {}},
    ]
    write_packages(original)
    clear_outputs()
    run_submission()
    validate_outputs(['A: 1.5.0', 'B: 2.5.0', 'C: 1.1.0', 'root: 1.0.0'], 4)

    token = secrets.token_hex(4).upper()
    count = 5 + secrets.randbelow(2)
    names = [f'P{token}_{index}' for index in range(count - 1)]
    packages = [{'name': 'root', 'version': '1.0.0', 'dependencies': {names[0]: '>=1.0.0'}}]
    selected = {'root': '1.0.0'}
    for index, name in enumerate(names):
        low = f'1.{index}.1'
        high = f'3.{index}.{2 + secrets.randbelow(7)}'
        next_name = names[index + 1] if index + 1 < len(names) else names[0]
        packages.append({'name': name, 'version': low, 'dependencies': {}})
        packages.append({'name': name, 'version': high, 'dependencies': {next_name: '>=1.0.0'}})
        selected[name] = high
    packages.append({'name': f'DECOY_{token}', 'version': '9.9.9', 'dependencies': {}})
    expected = [f'{name}: {selected[name]}' for name in sorted(selected)]

    write_packages(packages)
    clear_outputs()
    run_submission()
    validate_outputs(expected, count)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
