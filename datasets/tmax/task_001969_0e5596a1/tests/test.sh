#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import stat
import subprocess
import tempfile
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

SCRIPT = Path('/home/user/process_doc.sh')
INDEX = Path('/home/user/master_index.txt')
MAGIC = b'TECHDOC-V1'


def test_process_doc_script_exists_and_executable():
    assert SCRIPT.exists(), f'Script not found at {SCRIPT}'
    assert SCRIPT.is_file(), f'{SCRIPT} is not a file'
    assert not SCRIPT.is_symlink(), f'{SCRIPT} must be a regular script, not a symlink'
    st = os.stat(SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f'Script {SCRIPT} is not executable'


def encode_document(payload):
    # Match the memo and fixture generator: base64 output (including its newline),
    # then reverse every byte.
    return (base64.b64encode(payload) + b'\n')[::-1]


def decode_fixture(path):
    return base64.b64decode(path.read_bytes()[::-1])


def run_script(case):
    result = subprocess.run(
        ['bash', str(SCRIPT), str(case['input']), str(case['output'])],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    return case, result


def remove_index():
    if os.path.lexists(INDEX):
        os.unlink(INDEX)


def test_adversarial_corpus_randomized_paths_exact_decoding_and_concurrency():
    clean_dir = Path('/app/corpus/clean')
    evil_dir = Path('/app/corpus/evil')
    clean_files = list(clean_dir.iterdir()) if clean_dir.exists() else []
    evil_files = list(evil_dir.iterdir()) if evil_dir.exists() else []

    assert len(clean_files) > 0, 'No clean files found to test.'
    assert len(evil_files) > 0, 'No evil files found to test.'
    remove_index()

    with tempfile.TemporaryDirectory(prefix='doc-verifier-') as tmpdir:
        root = Path(tmpdir)
        input_dir = root / secrets.token_hex(8)
        output_dir = root / secrets.token_hex(8)
        input_dir.mkdir()
        output_dir.mkdir()
        cases = []

        # Preserve the supplied corpus checks, but compare every clean output to
        # its complete true decoding rather than merely checking the prefix.
        for source in clean_files:
            expected = decode_fixture(source)
            assert expected.startswith(MAGIC)
            cases.append({
                'input': source,
                'output': output_dir / f'out_{source.name}',
                'valid': True,
                'expected': expected,
            })

        for source in evil_files:
            cases.append({
                'input': source,
                'output': output_dir / f'out_{source.name}',
                'valid': False,
                'expected': None,
            })

        # Create fresh valid fixtures after the agent has finished. Their paths
        # contain no clean/evil marker and their exact payloads are unpredictable.
        generated_valid = []
        for i in range(24):
            payload = (
                b'TECHDOC-V1: randomized document ' + str(i).encode() + b' ' +
                secrets.token_bytes(24).hex().encode()
            )
            source = input_dir / uuid.uuid4().hex
            source.write_bytes(encode_document(payload))
            generated_valid.append(source)
            cases.append({
                'input': source,
                'output': output_dir / uuid.uuid4().hex,
                'valid': True,
                'expected': payload,
            })

        # Fresh invalid regular files with neutral randomized names.
        invalid_blobs = [
            encode_document(b'FAKEDOC: ' + secrets.token_bytes(20).hex().encode()),
            base64.b64encode(b'TECHDOC-V1: unreversed ' + secrets.token_bytes(12)) + b'\n',
            b'TECHDOC-V1: raw, not encoded ' + secrets.token_bytes(12),
            secrets.token_bytes(47),
            b'!!!!not-base64!!!!',
        ]
        generated_invalid = []
        for blob in invalid_blobs:
            source = input_dir / uuid.uuid4().hex
            source.write_bytes(blob)
            generated_invalid.append(source)
            cases.append({
                'input': source,
                'output': output_dir / uuid.uuid4().hex,
                'valid': False,
                'expected': None,
            })

        # Non-regular and symlink inputs must be rejected, including a symlink to
        # an otherwise valid document.
        directory_input = input_dir / uuid.uuid4().hex
        directory_input.mkdir()
        symlink_input = input_dir / uuid.uuid4().hex
        symlink_input.symlink_to(generated_valid[0])
        broken_input = input_dir / uuid.uuid4().hex
        broken_input.symlink_to(input_dir / uuid.uuid4().hex)
        loop_input = input_dir / uuid.uuid4().hex
        loop_input.symlink_to(loop_input)

        for source in (directory_input, symlink_input, broken_input, loop_input):
            cases.append({
                'input': source,
                'output': output_dir / uuid.uuid4().hex,
                'valid': False,
                'expected': None,
            })

        results = []
        with ThreadPoolExecutor(max_workers=16) as executor:
            futures = [executor.submit(run_script, case) for case in cases]
            for future in as_completed(futures):
                results.append(future.result())

        failures = []
        expected_basenames = []
        for case, result in results:
            output = case['output']
            if case['valid']:
                if result.returncode != 0:
                    failures.append(f"valid input failed: {case['input'].name}")
                    continue
                assert output.exists(), f'Output file {output} was not created for valid input'
                content = output.read_bytes()
                assert content.startswith(MAGIC), f'Decoded content for {case["input"].name} has wrong magic'
                assert content == case['expected'], f'Decoded content for {case["input"].name} is not exact'
                expected_basenames.append(output.name)
            else:
                if result.returncode == 0:
                    failures.append(f'invalid input accepted: {case["input"].name}')
                assert not os.path.lexists(output), f'Invalid input created output file {output}'

        if failures:
            raise AssertionError(' | '.join(failures))

        assert INDEX.exists(), f'Master index file {INDEX} was not created.'
        index_contents = INDEX.read_text().splitlines()
        actual_basenames = sorted(line.strip() for line in index_contents if line.strip())
        assert sorted(expected_basenames) == actual_basenames, (
            'Index file contents do not match expected output basenames.\n'
            f'Expected: {sorted(expected_basenames)}\nActual: {actual_basenames}'
        )

        # Rejection must neither overwrite an existing output nor modify the index.
        sentinel_output = output_dir / uuid.uuid4().hex
        sentinel = b'preexisting-output-' + secrets.token_bytes(16)
        sentinel_output.write_bytes(sentinel)
        index_before = INDEX.read_bytes()
        result = subprocess.run(
            ['bash', str(SCRIPT), str(generated_invalid[0]), str(sentinel_output)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 1, 'Invalid input did not exit with status 1'
        assert sentinel_output.read_bytes() == sentinel, 'Invalid input modified an existing output'
        assert INDEX.read_bytes() == index_before, 'Invalid input modified the master index'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
