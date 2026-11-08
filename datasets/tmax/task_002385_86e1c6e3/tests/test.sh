#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import re
import shutil
import string
import subprocess
from pathlib import Path

WORKSPACE = Path('/home/user/workspace')
BUILD = WORKSPACE / 'build'
LIBRARY = BUILD / 'libengine.so'
AGENT_SCRIPT = WORKSPACE / 'resolve.py'
ENGINE_SOURCE = WORKSPACE / 'engine.go'


class Node:
    def __init__(self, label=''):
        self.label = label
        self.children = []


def common_prefix_length(a, b):
    i = 0
    while i < len(a) and i < len(b) and a[i] == b[i]:
        i += 1
    return i


def insert(node, value):
    if not value:
        return

    for child in node.children:
        common = common_prefix_length(child.label, value)
        if common == 0:
            continue

        if common == len(child.label):
            insert(child, value[common:])
            return

        old_suffix = Node(child.label[common:])
        old_suffix.children = child.children
        child.label = child.label[:common]
        child.children = [old_suffix]

        new_suffix = value[common:]
        if new_suffix:
            child.children.append(Node(new_suffix))
        return

    node.children.append(Node(value))


def expected_output(input_data):
    root = Node()
    baseline = (1, 14, 0)

    for raw_line in input_data.splitlines():
        parts = raw_line.strip().split()
        if len(parts) != 2:
            continue
        package, version = parts
        try:
            fields = version.split('.')
            if len(fields) != 3:
                continue
            parsed = tuple(int(field) for field in fields)
        except ValueError:
            continue
        if parsed >= baseline:
            insert(root, package)

    lines = []

    def visit(node, depth):
        lines.append('  ' * depth + node.label)
        for child in node.children:
            visit(child, depth + 1)

    visit(root, 0)
    return '\n'.join(lines) + '\n'


def exported_functions():
    source = ENGINE_SOURCE.read_text()
    exports = re.findall(r'^\s*//export\s+([A-Za-z_]\w*)\s*$', source, re.MULTILINE)
    assert exports, 'engine.go does not declare any C-exported Go function'

    code_lines = [line for line in source.splitlines() if not line.lstrip().startswith('//')]
    code = '\n'.join(code_lines)
    assert re.search(r'\bgo\s+(?:func\s*\(|[A-Za-z_]\w*\s*\()', code), \
        'engine.go does not start comparison work in a goroutine'

    nm = subprocess.run(
        ['nm', '-D', '--defined-only', str(LIBRARY)],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert nm.returncode == 0, nm.stderr
    symbols = set(re.findall(r'\b([A-Za-z_]\w*)$', nm.stdout, re.MULTILINE))
    present = [name for name in exports if name in symbols]
    assert present, f'None of the //export functions are exported by libengine.so: {exports}'
    return present


def test_build_success_and_shared_library():
    assert AGENT_SCRIPT.is_file(), f'Agent script missing at {AGENT_SCRIPT}'
    assert ENGINE_SOURCE.is_file(), f'Go source missing at {ENGINE_SOURCE}'

    shutil.rmtree(BUILD, ignore_errors=True)
    BUILD.mkdir(parents=True)

    cmake_res = subprocess.run(
        ['cmake', '..'], cwd=BUILD, capture_output=True, text=True, timeout=60
    )
    assert cmake_res.returncode == 0, f'CMake failed:\n{cmake_res.stderr}'

    make_res = subprocess.run(
        ['make', '-j2'], cwd=BUILD, capture_output=True, text=True, timeout=120
    )
    assert make_res.returncode == 0, f'Make failed:\n{make_res.stderr}'

    assert LIBRARY.is_file(), 'CMake build did not produce build/libengine.so'
    assert LIBRARY.read_bytes()[:4] == b'\x7fELF', 'libengine.so is not an ELF artifact'

    try:
        ctypes.CDLL(str(LIBRARY))
    except OSError as exc:
        raise AssertionError(f'libengine.so cannot be dynamically loaded: {exc}')

    exported_functions()


def install_ctypes_audit_hook():
    hook_dir = Path('/tmp/resolver_audit_hook')
    shutil.rmtree(hook_dir, ignore_errors=True)
    hook_dir.mkdir()
    (hook_dir / 'sitecustomize.py').write_text(r'''
import os
import sys

log_path = os.environ.get('RESOLVER_AUDIT_LOG')
if log_path:
    def audit(event, args):
        if event in ('ctypes.dlopen', 'ctypes.dlsym'):
            with open(log_path, 'a', encoding='utf-8') as stream:
                stream.write(event + ' ' + repr(args) + '\n')
    sys.addaudithook(audit)
''')
    return hook_dir


def run_agent(input_data, run_number, exports, hook_dir):
    audit_log = Path(f'/tmp/resolver_audit_{run_number}.log')
    audit_log.unlink(missing_ok=True)

    env = os.environ.copy()
    prior_pythonpath = env.get('PYTHONPATH')
    env['PYTHONPATH'] = str(hook_dir) + (os.pathsep + prior_pythonpath if prior_pythonpath else '')
    env['RESOLVER_AUDIT_LOG'] = str(audit_log)

    result = subprocess.run(
        ['python3', str(AGENT_SCRIPT)],
        input=input_data,
        cwd=WORKSPACE,
        capture_output=True,
        text=True,
        env=env,
        timeout=20,
    )
    assert result.returncode == 0, \
        f'Agent script failed on run {run_number}:\n{result.stderr}\nInput:\n{input_data}'

    events = audit_log.read_text() if audit_log.exists() else ''
    assert 'ctypes.dlopen' in events and 'libengine.so' in events, \
        'resolve.py did not load libengine.so through ctypes'
    assert 'ctypes.dlsym' in events and any(name in events for name in exports), \
        'resolve.py did not resolve a C-exported Go comparison function through ctypes'

    expected = expected_output(input_data)
    assert result.stdout == expected, \
        f'Mismatch on run {run_number}.\nInput:\n{input_data}\nExpected:\n{expected!r}\nActual:\n{result.stdout!r}'


def generate_fuzz_input():
    num_lines = random.randint(10, 100)
    lines = []
    for _ in range(num_lines):
        name_len = random.randint(3, 8)
        name = ''.join(random.choices(string.ascii_lowercase, k=name_len))
        major = random.randint(0, 9)
        minor = random.randint(0, 99)
        patch = random.randint(0, 99)
        lines.append(f'{name} {major}.{minor}.{patch}')
    return '\n'.join(lines) + '\n'


def test_resolver_behavior_and_ctypes_integration():
    exports = exported_functions()
    hook_dir = install_ctypes_audit_hook()

    targeted = '''app 1.14.0
apple 1.14.1
application 2.0.0
apt 1.13.99
car 0.99.99
carbon 1.15.0
cart 3.0.0
dog 1.14.0
dove 1.13.0
app 5.0.0
'''
    run_agent(targeted, 0, exports, hook_dir)

    random.seed(42)
    for i in range(50):
        run_agent(generate_fuzz_input(), i + 1, exports, hook_dir)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
