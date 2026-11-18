#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import sqlite3
import subprocess
import tempfile
import numpy as np

FRAMES_DIR = '/home/user/frames'
DB_PATH = '/home/user/analytics.db'
SRC_DIR = '/home/user/src'
EXECUTABLE = os.path.join(SRC_DIR, 'motion_analyzer')


def extract_reference_frames(out_dir):
    subprocess.run([
        'ffmpeg', '-y', '-i', '/app/video.mp4', '-r', '10',
        '-pix_fmt', 'gray', os.path.join(out_dir, '%04d.pgm')
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)


def read_pgm(path):
    with open(path, 'rb') as f:
        assert f.readline().strip() == b'P5'
        line = f.readline()
        while line.startswith(b'#'):
            line = f.readline()
        width, height = map(int, line.split())
        maxval = int(f.readline())
        assert maxval == 255
        data = f.read(width * height)
        assert len(data) == width * height
    return np.frombuffer(data, dtype=np.uint8).astype(np.float64)


def expected_values(frames_dir):
    names = sorted(f for f in os.listdir(frames_dir) if f.endswith('.pgm'))
    assert len(names) == 10, f'Expected 10 PGM frames, got {len(names)}.'
    expected = {}
    previous = read_pgm(os.path.join(frames_dir, names[0]))
    for frame_num, name in enumerate(names[1:], start=2):
        current = read_pgm(os.path.join(frames_dir, name))
        assert current.shape == previous.shape
        expected[frame_num] = float(np.mean(np.abs(current - previous)))
        previous = current
    return expected


def test_frames_extracted():
    assert os.path.isdir(FRAMES_DIR), f'Directory {FRAMES_DIR} is missing.'
    expected_names = [f'{i:04d}.pgm' for i in range(1, 11)]
    names = sorted(f for f in os.listdir(FRAMES_DIR) if f.endswith('.pgm'))
    assert names == expected_names, f'Expected frames {expected_names}, got {names}.'
    for name in names:
        read_pgm(os.path.join(FRAMES_DIR, name))


def test_db_schema_updated():
    assert os.path.isfile(DB_PATH), f'{DB_PATH} missing.'
    with sqlite3.connect(DB_PATH) as conn:
        columns = {row[1]: row[2].upper() for row in conn.execute('PRAGMA table_info(frame_stats)')}
    assert 'diff_score' in columns, "Column 'diff_score' missing in frame_stats."
    assert columns['diff_score'] == 'REAL', "Column 'diff_score' must be REAL."
    assert 'timestamp_ms' in columns, "Column 'timestamp_ms' missing in frame_stats."
    assert columns['timestamp_ms'] == 'INTEGER', "Column 'timestamp_ms' must be INTEGER."


def test_build_patch_and_executable_behavior():
    assert os.path.isfile(os.path.join(SRC_DIR, 'Makefile')), 'Makefile missing.'
    assert os.path.isfile(os.path.join(SRC_DIR, 'list.c')), 'list.c missing.'
    list_source = open(os.path.join(SRC_DIR, 'list.c'), encoding='utf-8').read()
    assert 'n->prev = list->tail;' in list_source, 'The supplied list patch was not applied.'

    subprocess.run(['make', 'clean'], cwd=SRC_DIR, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    subprocess.run(['make'], cwd=SRC_DIR, stdout=subprocess.PIPE,
                   stderr=subprocess.PIPE, text=True, check=True)
    assert os.path.isfile(EXECUTABLE) and os.access(EXECUTABLE, os.X_OK), \
        'motion_analyzer was not built as an executable.'

    with tempfile.TemporaryDirectory() as tmpdir:
        frames_dir = os.path.join(tmpdir, 'frames')
        os.mkdir(frames_dir)
        extract_reference_frames(frames_dir)
        expected = expected_values(frames_dir)

        test_db = os.path.join(tmpdir, 'analytics.db')
        with sqlite3.connect(test_db) as conn:
            conn.execute('CREATE TABLE frame_stats (id INTEGER PRIMARY KEY, frame_num INTEGER, diff_score REAL, timestamp_ms INTEGER)')
            conn.executemany('INSERT INTO frame_stats(frame_num) VALUES (?)', [(i,) for i in range(1, 11)])

        subprocess.run([EXECUTABLE, frames_dir, test_db], cwd=SRC_DIR,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       text=True, timeout=30, check=True)

        with sqlite3.connect(test_db) as conn:
            rows = conn.execute('SELECT frame_num, diff_score, timestamp_ms FROM frame_stats ORDER BY frame_num').fetchall()

        # Frame 1 is a setup row and has no preceding transition; it need not be deleted.
        assert len(rows) == 10, f'Analyzer changed the seeded row count: got {len(rows)}.'
        first = rows[0]
        assert first[0] == 1 and first[1] is None and first[2] is None, \
            'Frame 1 must remain an uncomputed seed row.'
        assert [r[0] for r in rows[1:]] == list(range(2, 11))
        errors = []
        for frame_num, score, timestamp in rows[1:]:
            assert score is not None, f'Missing diff_score for frame {frame_num}.'
            assert timestamp == (frame_num - 1) * 100
            errors.append((score - expected[frame_num]) ** 2)
        assert float(np.mean(errors)) <= 0.05


def test_final_db_contents_and_mse():
    with tempfile.TemporaryDirectory() as tmpdir:
        extract_reference_frames(tmpdir)
        expected = expected_values(tmpdir)

    with sqlite3.connect(DB_PATH) as conn:
        rows = conn.execute('SELECT frame_num, diff_score, timestamp_ms FROM frame_stats ORDER BY frame_num').fetchall()

    # The initial frame-1 row is valid because results are only defined for transitions ending at 2..10.
    assert len(rows) == 10, f'Expected the 10 prepopulated rows to remain, got {len(rows)}.'
    assert rows[0][0] == 1 and rows[0][1] is None and rows[0][2] is None, \
        'Frame 1 should have no transition result.'
    assert [row[0] for row in rows[1:]] == list(range(2, 11))

    errors = []
    for frame_num, diff_score, timestamp_ms in rows[1:]:
        assert diff_score is not None, f'Missing diff_score for frame {frame_num}.'
        assert timestamp_ms == (frame_num - 1) * 100, \
            f'Incorrect timestamp for frame {frame_num}.'
        errors.append((diff_score - expected[frame_num]) ** 2)
    mse = float(np.mean(errors))
    assert mse <= 0.05, f'MSE of diff_score is {mse:.4f}, which is > 0.05 threshold.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
