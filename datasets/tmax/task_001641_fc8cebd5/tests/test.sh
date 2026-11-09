#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import subprocess
import pytest

SCRIPT = '/home/user/detect_deadlocks.sh'
TTL = '/home/user/transactions.ttl'
JSON_PATH = '/home/user/deadlocks.json'
JENA_DIR = '/home/user/jena'
ORIGINAL_TTL = '''@prefix ex: <http://example.org/> .

ex:T1 ex:waitsFor ex:R1 .
ex:R1 ex:heldBy ex:T2 .
ex:T2 ex:waitsFor ex:R2 .
ex:R2 ex:heldBy ex:T1 .

ex:T3 ex:waitsFor ex:R3 .
ex:R3 ex:heldBy ex:T4 .

ex:T5 ex:waitsFor ex:R4 .
ex:R4 ex:heldBy ex:T6 .
ex:T6 ex:waitsFor ex:R5 .
ex:R5 ex:heldBy ex:T5 .
'''


def run_script(env):
    result = subprocess.run(
        [SCRIPT], cwd='/home/user', env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=300
    )
    assert result.returncode == 0, f'Script failed with output:\n{result.stdout}'


def read_json_strict(expected):
    assert os.path.isfile(JSON_PATH), f'Output file {JSON_PATH} does not exist.'
    with open(JSON_PATH, 'r') as f:
        raw = f.read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        pytest.fail(f'File {JSON_PATH} does not contain valid JSON: {exc}')
    assert data == expected, f'Expected {expected}, got {data}'
    assert raw == json.dumps(expected, indent=2) + '\n', 'JSON is not in the required exact format.'


def test_script_executes_real_jena_and_handles_unseen_graph():
    assert os.path.isfile(SCRIPT), f'Script {SCRIPT} does not exist.'
    assert os.access(SCRIPT, os.X_OK), f'Script {SCRIPT} is not executable.'
    with open(SCRIPT, 'r', errors='replace') as f:
        script_text = f.read()
    assert 'https://archive.apache.org/dist/jena/binaries/apache-jena-4.9.0.tar.gz' in script_text, \
        'Script does not specify the required Apache Jena download.'
    assert re.search(r'(^|[/[:space:]])sparql([[:space:]]|$)', script_text) or 'sparql' in script_text, \
        'Script does not invoke the Jena sparql tool.'

    token = secrets.token_hex(8)
    tx = [f'Q{token}_{letter}' for letter in ('A', 'B', 'C', 'D', 'E', 'F', 'G')]
    resources = [f'R{token}_{i}' for i in range(1, 8)]
    triples = [
        (tx[0], 'waitsFor', resources[0]), (resources[0], 'heldBy', tx[1]),
        (tx[1], 'waitsFor', resources[1]), (resources[1], 'heldBy', tx[0]),
        (tx[2], 'waitsFor', resources[2]), (resources[2], 'heldBy', tx[3]),
        (tx[3], 'waitsFor', resources[3]), (resources[3], 'heldBy', tx[2]),
        (tx[4], 'waitsFor', resources[4]), (resources[4], 'heldBy', tx[5]),
        (tx[5], 'waitsFor', resources[5]), (resources[5], 'heldBy', tx[6]),
        (tx[6], 'waitsFor', resources[6]), (resources[6], 'heldBy', tx[4]),
    ]
    with open(TTL, 'w') as f:
        f.write('@prefix ex: <http://example.org/> .\n\n')
        for subject, predicate, obj in triples:
            f.write(f'ex:{subject} ex:{predicate} ex:{obj} .\n')

    expected = []
    edges = set()
    waits = [(s, o) for s, p, o in triples if p == 'waitsFor']
    holders = {s: o for s, p, o in triples if p == 'heldBy'}
    for transaction, resource in waits:
        if resource in holders:
            edges.add((transaction, holders[resource]))
    for first, second in edges:
        if first < second and (second, first) in edges:
            expected.append({'tx1': first, 'tx2': second})
    expected.sort(key=lambda item: item['tx1'])

    shutil.rmtree(JENA_DIR, ignore_errors=True)
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)

    wrapper_home = '/tmp/verifier-java-home'
    marker = '/tmp/jena-java-invocations'
    shutil.rmtree(wrapper_home, ignore_errors=True)
    os.makedirs(os.path.join(wrapper_home, 'bin'))
    wrapper = os.path.join(wrapper_home, 'bin', 'java')
    with open(wrapper, 'w') as f:
        f.write('#!/bin/bash\nprintf "%s\\n" "$*" >> "' + marker + '"\nexec /usr/bin/java "$@"\n')
    os.chmod(wrapper, 0o755)
    if os.path.exists(marker):
        os.remove(marker)

    env = os.environ.copy()
    env['JAVA_HOME'] = wrapper_home
    env['JAVA'] = wrapper
    env['PATH'] = os.path.join(wrapper_home, 'bin') + ':' + env.get('PATH', '')
    run_script(env)
    read_json_strict(expected)

    assert os.path.isfile(marker), 'The script did not launch Java through Jena.'
    with open(marker, 'r', errors='replace') as f:
        invocations = f.read()
    assert 'arq.sparql' in invocations, 'The script did not invoke Apache Jena sparql.'

    sparql_candidates = []
    for root, dirs, files in os.walk(JENA_DIR):
        if 'sparql' in files:
            candidate = os.path.join(root, 'sparql')
            if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                sparql_candidates.append(candidate)
    assert sparql_candidates, "Jena 'sparql' executable not found in /home/user/jena."

    genuine = None
    for candidate in sparql_candidates:
        result = subprocess.run([candidate, '--version'], stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, timeout=60)
        if result.returncode == 0 and '4.9.0' in result.stdout:
            genuine = candidate
            break
    assert genuine is not None, 'No working Apache Jena 4.9.0 sparql executable was found.'

    probe_ttl = '/tmp/verifier-probe.ttl'
    probe_query = '/tmp/verifier-probe.rq'
    with open(probe_ttl, 'w') as f:
        f.write('@prefix ex: <http://example.org/> .\nex:VerifierProbe ex:p ex:o .\n')
    with open(probe_query, 'w') as f:
        f.write('SELECT ?s WHERE { ?s <http://example.org/p> <http://example.org/o> }\n')
    probe = subprocess.run([genuine, '--data=' + probe_ttl, '--query=' + probe_query],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, timeout=60)
    assert probe.returncode == 0 and 'VerifierProbe' in probe.stdout, \
        f'Installed sparql tool is not functional:\n{probe.stdout}'

    # Restore the supplied snapshot and execute again so the original assertions remain tested.
    with open(TTL, 'w') as f:
        f.write(ORIGINAL_TTL)
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    run_script(env)


def test_script_exists_and_executable():
    """Test that the bash script exists and is executable."""
    script_path = '/home/user/detect_deadlocks.sh'
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_jena_extracted():
    """Test that Apache Jena was extracted to the correct directory."""
    jena_dir = '/home/user/jena'
    assert os.path.isdir(jena_dir), f"Directory {jena_dir} does not exist."
    sparql_found = False
    for root, dirs, files in os.walk(jena_dir):
        if 'sparql' in files:
            sparql_found = True
            break
    assert sparql_found, "Jena 'sparql' binary not found in /home/user/jena."


def test_deadlocks_json_exists():
    """Test that the output deadlocks.json exists."""
    json_path = '/home/user/deadlocks.json'
    assert os.path.isfile(json_path), f"Output file {json_path} does not exist."


def test_deadlocks_json_content():
    """Test that deadlocks.json contains the correct deadlock pairs."""
    json_path = '/home/user/deadlocks.json'
    assert os.path.isfile(json_path), f"Output file {json_path} does not exist."

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} does not contain valid JSON.")

    assert isinstance(data, list), f"Expected JSON array, got {type(data).__name__}."

    expected_data = [
        {"tx1": "T1", "tx2": "T2"},
        {"tx1": "T5", "tx2": "T6"}
    ]

    try:
        sorted_data = sorted(data, key=lambda x: x.get('tx1', ''))
    except TypeError:
        pytest.fail("Elements in JSON array are not dictionaries as expected.")

    assert sorted_data == expected_data, f"JSON content does not match expected deadlocks. Got: {sorted_data}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
