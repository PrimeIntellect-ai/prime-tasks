#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import subprocess
import pytest

HOME = '/home/user'
SOURCE = os.path.join(HOME, 'audit.c')
AUDIT = os.path.join(HOME, 'audit')
OUTPUT = os.path.join(HOME, 'vulnerable_pii.txt')
COMPONENTS = os.path.join(HOME, 'components.csv')
FLOWS = os.path.join(HOME, 'data_flows.csv')
COMPILED_SOURCE = '/tmp/audit_from_source'

ORIGINAL_COMPONENTS = '''1,Public
2,Internal
3,Encryption
4,Internal
5,PII
6,Internal
7,PII
8,Encryption
9,Public
10,PII
11,Public
12,Internal
13,PII
14,Internal
15,PII
'''

ORIGINAL_FLOWS = '''1,2
2,3
3,4
4,5
1,6
6,7
9,8
8,10
9,6
11,12
12,13
12,8
8,15
'''


def write_inputs(component_text, flow_text):
    with open(COMPONENTS, 'w') as f:
        f.write(component_text)
    with open(FLOWS, 'w') as f:
        f.write(flow_text)


def demote_to_user():
    account = pwd.getpwnam('user')
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def run_and_check(binary, expected):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    result = subprocess.run(
        [binary],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
        preexec_fn=demote_to_user,
    )
    assert result.returncode == 0, (
        f'{binary} exited with status {result.returncode}. stderr: {result.stderr}'
    )
    assert os.path.isfile(OUTPUT), f'Output file {OUTPUT} is missing after running {binary}.'

    with open(OUTPUT, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [str(value) for value in sorted(expected)]
    assert lines == expected_lines, (
        f'Content of {OUTPUT} is incorrect for the supplied graph. '
        f'Expected {expected_lines}, got {lines}.'
    )


def graph_answer(components, edges):
    types = dict(components)
    adjacency = {comp_id: [] for comp_id, _ in components}
    for source, dest in edges:
        if source in adjacency and dest in types:
            adjacency[source].append(dest)

    queue = [comp_id for comp_id, comp_type in components if comp_type == 'Public']
    visited = set(queue)
    vulnerable = set()

    while queue:
        current = queue.pop(0)
        if types[current] == 'PII':
            vulnerable.add(current)
        for dest in adjacency[current]:
            if types[dest] == 'Encryption':
                continue
            if dest not in visited:
                visited.add(dest)
                queue.append(dest)

    return sorted(vulnerable)


def encode_case(components, edges):
    component_text = ''.join(f'{comp_id},{comp_type}\n' for comp_id, comp_type in components)
    flow_text = ''.join(f'{source},{dest}\n' for source, dest in edges)
    return component_text, flow_text


def generated_cases():
    crafted_components = [
        (101, 'Public'), (205, 'Internal'), (309, 'Encryption'),
        (401, 'PII'), (502, 'PII'), (603, 'Internal'),
        (704, 'PII'), (805, 'Encryption'), (906, 'PII'),
        (77, 'Public'), (88, 'PII'), (99, 'Internal'),
    ]
    crafted_edges = [
        (101, 205), (205, 309), (309, 401),
        (205, 502), (502, 603), (603, 704),
        (603, 205), (77, 99), (99, 805), (805, 906),
    ]
    yield crafted_components, crafted_edges

    rng = random.SystemRandom()
    for _ in range(10):
        count = rng.randint(20, 38)
        ids = rng.sample(range(1, 1000), count)
        component_types = ['Public'] * 3 + ['Encryption'] * 3 + ['PII'] * 6
        component_types += [rng.choice(['Public', 'Internal', 'Encryption', 'PII'])
                            for _ in range(count - len(component_types))]
        rng.shuffle(component_types)
        components = list(zip(ids, component_types))
        rng.shuffle(components)

        edges = []
        for source in ids:
            for dest in ids:
                if source != dest and rng.random() < 0.09:
                    edges.append((source, dest))
        rng.shuffle(edges)
        yield components, edges


def test_audit_c_exists():
    assert os.path.isfile(SOURCE), f'Source file {SOURCE} is missing.'


def test_audit_executable_exists():
    assert os.path.isfile(AUDIT), f'Executable {AUDIT} is missing.'
    assert os.access(AUDIT, os.X_OK), f'File {AUDIT} is not executable.'
    with open(AUDIT, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'File {AUDIT} is not a compiled executable.'


def test_program_behavior_and_output():
    assert os.path.isfile(SOURCE), f'Source file {SOURCE} is missing.'
    assert os.path.isfile(AUDIT), f'Executable {AUDIT} is missing.'
    assert os.access(AUDIT, os.X_OK), f'File {AUDIT} is not executable.'

    compile_result = subprocess.run(
        ['gcc', '-std=c11', '-O2', SOURCE, '-o', COMPILED_SOURCE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert compile_result.returncode == 0, (
        f'{SOURCE} does not compile successfully: {compile_result.stderr}'
    )

    try:
        # Preserve the original exact check, but first require the submitted
        # executable to produce it from the canonical supplied inputs.
        write_inputs(ORIGINAL_COMPONENTS, ORIGINAL_FLOWS)
        run_and_check(AUDIT, [7, 13])

        with open(OUTPUT, 'r') as f:
            lines = [line.strip() for line in f if line.strip()]
        expected_lines = ['7', '13']
        assert lines == expected_lines, (
            f'Content of {OUTPUT} is incorrect. Expected {expected_lines}, got {lines}.'
        )

        write_inputs(ORIGINAL_COMPONENTS, ORIGINAL_FLOWS)
        run_and_check(COMPILED_SOURCE, [7, 13])

        # Exercise both the submitted executable and a fresh build of audit.c
        # on graphs whose expected results are independently derived here.
        for components, edges in generated_cases():
            component_text, flow_text = encode_case(components, edges)
            expected = graph_answer(components, edges)

            write_inputs(component_text, flow_text)
            run_and_check(AUDIT, expected)

            write_inputs(component_text, flow_text)
            run_and_check(COMPILED_SOURCE, expected)
    finally:
        write_inputs(ORIGINAL_COMPONENTS, ORIGINAL_FLOWS)


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
