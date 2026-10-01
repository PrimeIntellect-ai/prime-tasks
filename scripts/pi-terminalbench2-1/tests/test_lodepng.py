import subprocess
from pathlib import Path

import pytest

TASK = Path(__file__).parents[3] / "datasets/pi-terminalbench2-1/pytorch-model-cli"


@pytest.mark.parametrize(
    ("compiler", "language", "standard"), [("cc", "c", "c89"), ("c++", "c++", "c++11")]
)
def test_lodepng_overflow_and_pixel_roundtrips(tmp_path, compiler, language, standard):
    executable = tmp_path / "lodepng-check"
    subprocess.run(
        [
            compiler,
            "-x",
            language,
            f"-std={standard}",
            "-I",
            str(TASK / "environment/task-deps"),
            str(Path(__file__).with_name("lodepng_check.c")),
            "-o",
            str(executable),
        ],
        check=True,
    )
    subprocess.run(
        [str(executable), str(TASK / "environment/task-deps/image.png")], check=True
    )
