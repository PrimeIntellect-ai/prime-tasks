#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import shutil
import struct
import subprocess
import zlib

PROJECT = '/home/user/etl_pipeline'
INPUT = '/home/user/data/input.csv'
OUTPUT = '/home/user/output'
METRICS = os.path.join(OUTPUT, 'metrics.json')
SCATTER = os.path.join(OUTPUT, 'scatter.png')
TARGET = '/tmp/verifier-target'
BINARY = os.path.join(TARGET, 'debug', 'etl_pipeline')

ORIGINAL_ROWS = [
    ['id', 'text'],
    ['1', 'hello'],
    ['2', ''],
    ['3', 'world'],
    ['4', 'this_is_a_very_long_string_that_exceeds_the_limit_of_fifty_characters'],
    ['5', 'rust'],
]


def write_rows(rows):
    os.makedirs(os.path.dirname(INPUT), exist_ok=True)
    with open(INPUT, 'w', newline='', encoding='utf-8') as f:
        csv.writer(f, lineterminator='\n').writerows(rows)


def expected_metrics(rows):
    missing = 0
    outliers = 0
    valid = 0
    for row in rows[1:]:
        text = row[1]
        if text == '':
            missing += 1
        elif len(text.encode('utf-8')) > 50:
            outliers += 1
        else:
            valid += 1
    return {
        'missing_dropped': missing,
        'outliers_dropped': outliers,
        'valid_records': valid,
    }


def read_metrics(expected):
    assert os.path.exists(METRICS), f'{METRICS} does not exist. Did you run the pipeline and output the metrics?'
    try:
        with open(METRICS, encoding='utf-8') as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'{METRICS} is not a valid JSON file.') from exc

    assert 'missing_dropped' in data, "metrics.json is missing the 'missing_dropped' key."
    assert 'outliers_dropped' in data, "metrics.json is missing the 'outliers_dropped' key."
    assert 'valid_records' in data, "metrics.json is missing the 'valid_records' key."
    assert set(data) == set(expected), f'metrics.json has unexpected keys: {set(data) - set(expected)}'
    assert data['missing_dropped'] == expected['missing_dropped'], \
        f"Expected {expected['missing_dropped']} missing_dropped, got {data['missing_dropped']}"
    assert data['outliers_dropped'] == expected['outliers_dropped'], \
        f"Expected {expected['outliers_dropped']} outliers_dropped, got {data['outliers_dropped']}"
    assert data['valid_records'] == expected['valid_records'], \
        f"Expected {expected['valid_records']} valid_records, got {data['valid_records']}"


def decode_png(path):
    assert os.path.exists(path), f'{path} does not exist. Did you generate the scatter plot?'
    blob = open(path, 'rb').read()
    assert blob.startswith(b'\x89PNG\r\n\x1a\n'), f'{path} is not a PNG file'

    pos = 8
    width = height = bit_depth = color_type = interlace = None
    compressed = bytearray()
    saw_iend = False
    while pos + 12 <= len(blob):
        length = struct.unpack('>I', blob[pos:pos + 4])[0]
        kind = blob[pos + 4:pos + 8]
        start = pos + 8
        end = start + length
        assert end + 4 <= len(blob), 'truncated PNG chunk'
        payload = blob[start:end]
        expected_crc = struct.unpack('>I', blob[end:end + 4])[0]
        assert (zlib.crc32(kind + payload) & 0xffffffff) == expected_crc, 'invalid PNG CRC'
        pos = end + 4
        if kind == b'IHDR':
            assert length == 13, 'invalid PNG header'
            width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack('>IIBBBBB', payload)
            assert compression == 0 and filtering == 0
        elif kind == b'IDAT':
            compressed.extend(payload)
        elif kind == b'IEND':
            saw_iend = True
            break

    assert saw_iend and width and height and compressed, 'incomplete PNG'
    assert bit_depth == 8, 'scatter PNG must use ordinary 8-bit pixels'
    assert interlace == 0, 'interlaced PNG is unsupported by this validation'
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(color_type)
    assert channels is not None, f'unsupported PNG color type {color_type}'

    raw = zlib.decompress(bytes(compressed))
    stride = width * channels
    assert len(raw) == height * (stride + 1), 'invalid decompressed PNG size'
    rows = []
    previous = bytearray(stride)
    offset = 0
    for _ in range(height):
        filter_type = raw[offset]
        encoded = raw[offset + 1:offset + 1 + stride]
        offset += stride + 1
        decoded = bytearray(stride)
        for i, value in enumerate(encoded):
            left = decoded[i - channels] if i >= channels else 0
            up = previous[i]
            upper_left = previous[i - channels] if i >= channels else 0
            if filter_type == 0:
                predictor = 0
            elif filter_type == 1:
                predictor = left
            elif filter_type == 2:
                predictor = up
            elif filter_type == 3:
                predictor = (left + up) // 2
            elif filter_type == 4:
                p = left + up - upper_left
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - upper_left)
                predictor = left if pa <= pb and pa <= pc else (up if pb <= pc else upper_left)
            else:
                raise AssertionError(f'invalid PNG filter {filter_type}')
            decoded[i] = (value + predictor) & 0xff
        rows.append(bytes(decoded))
        previous = decoded

    pixels = b''.join(rows)
    distinct = {pixels[i:i + channels] for i in range(0, len(pixels), channels)}
    assert len(distinct) >= 3, 'scatter image has insufficient visual content'
    return width, height, channels, pixels


def run_pipeline(rows):
    write_rows(rows)
    os.makedirs(OUTPUT, exist_ok=True)
    for path in (METRICS, SCATTER):
        if os.path.lexists(path):
            os.remove(path)
    subprocess.run([BINARY], cwd=PROJECT, check=True, timeout=120)
    read_metrics(expected_metrics(rows))
    return decode_png(SCATTER)


def changed_pixels(a, b):
    assert a[:3] == b[:3], 'plot geometry or pixel format changed for equivalent-size datasets'
    channels = a[2]
    return sum(
        a[3][i:i + channels] != b[3][i:i + channels]
        for i in range(0, len(a[3]), channels)
    )


def test_built_rust_pipeline_and_outputs():
    main_rs = os.path.join(PROJECT, 'src', 'main.rs')
    cargo_toml = os.path.join(PROJECT, 'Cargo.toml')
    assert os.path.isfile(main_rs), 'src/main.rs is missing'
    assert os.path.isfile(cargo_toml), 'Cargo.toml is missing'
    source = open(main_rs, encoding='utf-8').read()
    assert 'Please implement the ETL pipeline here.' not in source, 'the starter Rust program was not implemented'

    shutil.rmtree(TARGET, ignore_errors=True)
    subprocess.run(
        ['cargo', 'build', '--manifest-path', cargo_toml, '--target-dir', TARGET],
        cwd=PROJECT, check=True, timeout=300,
    )
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), 'cargo did not produce the ETL executable'
    with open(BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'the built artifact is not a native executable'

    try:
        # Hidden filtering case: expected values are derived from the generated CSV.
        missing_count = 2 + secrets.randbelow(3)
        outlier_count = 1 + secrets.randbelow(3)
        valid_count = 4 + secrets.randbelow(4)
        rows = [['id', 'text']]
        next_id = 1
        for _ in range(missing_count):
            rows.append([str(next_id), ''])
            next_id += 1
        for _ in range(outlier_count):
            rows.append([str(next_id), 'q' * (51 + secrets.randbelow(20))])
            next_id += 1
        for _ in range(valid_count):
            length = 1 + secrets.randbelow(50)
            char = chr(ord('a') + secrets.randbelow(26))
            rows.append([str(next_id), char * length])
            next_id += 1
        run_pipeline(rows)

        # Keep extrema and record count fixed while moving one interior feature.
        # A real scatter plot must change, while an empty chart with the same axes cannot.
        min_x = 4 + secrets.randbelow(4)
        max_x = 34 + secrets.randbelow(10)
        first_mid = min_x + 4
        second_mid = max_x - 5
        common = [
            ['id', 'text'],
            ['1', 'A' * min_x],
            ['2', 'Z' * max_x],
            ['3', 'M' * ((min_x + max_x) // 2)],
        ]
        rows_a = common + [['4', 'H' * first_mid]]
        rows_b = common + [['4', 'T' * second_mid]]

        image_a1 = run_pipeline(rows_a)
        image_a2 = run_pipeline(rows_a)
        assert image_a1 == image_a2, 'rendering is not deterministic for identical input'
        image_b = run_pipeline(rows_b)
        difference = changed_pixels(image_a1, image_b)
        total_pixels = image_a1[0] * image_a1[1]
        assert difference >= 2, 'scatter.png does not visually respond to changed point coordinates'
        assert difference < max(20, total_pixels // 5), 'changing one point unexpectedly replaced most of the image'
    finally:
        # Leave and validate the outputs requested for the original supplied CSV.
        write_rows(ORIGINAL_ROWS)
        for path in (METRICS, SCATTER):
            if os.path.lexists(path):
                os.remove(path)
        subprocess.run([BINARY], cwd=PROJECT, check=True, timeout=120)

    read_metrics({'missing_dropped': 1, 'outliers_dropped': 1, 'valid_records': 3})
    decode_png(SCATTER)
    size = os.path.getsize(SCATTER)
    assert size > 3000, f'{SCATTER} is too small ({size} bytes). It appears to be blank or corrupted. Ensure the drawing context is properly handled.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
