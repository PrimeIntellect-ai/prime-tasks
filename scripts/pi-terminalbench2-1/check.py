# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "numpy>=2,<3",
#   "protobuf>=5",
#   "psutil>=6",
#   "pytest==8.4.1",
#   "requests>=2,<3",
#   "torch==2.7.1",
#   "transformers==4.56.0",
#   "verifiers[harbor]==0.3.2.dev162",
# ]
# ///
"""Run PI-TerminalBench2.1's author-side grader regression tests."""

import sys
from pathlib import Path

import pytest

raise SystemExit(pytest.main([str(Path(__file__).parent / "tests"), *sys.argv[1:]]))
