#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_outputs.py
import os
import numpy as np
import h5py


def parse_fasta_weights(path):
    sequences = []
    current = []
    with open(path, "r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if current:
                    sequences.append("".join(current))
                    current = []
            else:
                current.append(line)
    if current:
        sequences.append("".join(current))
    assert len(sequences) == 5, f"Expected 5 FASTA sequences, found {len(sequences)}"
    return np.asarray([len(seq) * 110.0 for seq in sequences], dtype=float)


def exact_trajectory(y0, times):
    # A has diagonal -0.1 and off-diagonal 0.01. Its common mode has
    # eigenvalue -0.06, while all deviations from the mean have -0.11.
    mean = np.mean(y0)
    return (mean * np.exp(-0.06 * times[:, None])
            + (y0[None, :] - mean) * np.exp(-0.11 * times[:, None]))


def test_training_data_exists_and_valid():
    h5_path = "/home/user/training_data.h5"
    assert os.path.isfile(h5_path), f"File {h5_path} does not exist."

    with open(h5_path, "rb") as f:
        assert f.read(8) == b"\x89HDF\r\n\x1a\n", f"File {h5_path} is not a valid HDF5 file."

    expected_y0 = parse_fasta_weights("/home/user/input.fasta")
    np.testing.assert_allclose(
        expected_y0, [550.0, 2200.0, 330.0, 440.0, 660.0], atol=1e-12
    )
    times = np.linspace(0.0, 100.0, 1000)
    expected = exact_trajectory(expected_y0, times)

    with h5py.File(h5_path, "r") as f:
        assert "simulated_trajectories" in f, "Dataset 'simulated_trajectories' not found in HDF5 file."
        dataset = f["simulated_trajectories"]
        assert dataset.shape == (1000, 5), f"Expected shape (1000, 5), got {dataset.shape}"
        assert np.issubdtype(dataset.dtype, np.number), "Trajectory dataset must be numerical."
        data = dataset[:]

    assert np.all(np.isfinite(data)), "Trajectory contains NaN or infinite values."
    np.testing.assert_allclose(
        data[0], expected_y0, rtol=0.0, atol=1e-5,
        err_msg="Initial conditions do not match the FASTA-derived values."
    )
    # Validate every sample, which also verifies evaluation at the required
    # 1000 evenly spaced times rather than merely checking the endpoints.
    np.testing.assert_allclose(
        data, expected, rtol=2e-3, atol=1e-2,
        err_msg="The stored trajectory does not solve the stated ODE on the required time grid."
    )
    np.testing.assert_allclose(
        data[-1], expected[-1], rtol=5e-4, atol=1e-3,
        err_msg="Final row does not match the stated ODE at t=100."
    )


def expected_euler_y1():
    y = parse_fasta_weights("/home/user/input.fasta")
    values = [y[0]]
    for _ in range(4):
        derivative = -0.1 * y + 0.01 * (np.sum(y) - y)
        y = y + 25.0 * derivative
        values.append(y[0])
    return np.asarray(values)


def image_contains_euler_curve(rgb, expected_values):
    """Find a long, consistently colored component with the Euler curve's shape.

    Plot coordinates may have arbitrary margins, size, and axis limits, so both
    pixel axes are fitted affinely. The trajectory itself must retain the
    expected piecewise-linear shape through all five Euler samples.
    """
    from scipy import ndimage

    height, width, _ = rgb.shape
    colors, counts = np.unique(rgb.reshape(-1, 3), axis=0, return_counts=True)
    order = np.argsort(counts)[::-1]

    # Frequent exact colors include the solid core of anti-aliased matplotlib
    # lines. Ignore only near-white backgrounds and inspect ample candidates.
    candidates = []
    for idx in order:
        color = colors[idx]
        count = counts[idx]
        if count < 20:
            break
        if np.all(color >= 245):
            continue
        candidates.append(color)
        if len(candidates) >= 100:
            break

    def matches(points_y, points_x):
        if len(points_x) < 30:
            return False
        unique_x = np.unique(points_x)
        if len(unique_x) < 25 or unique_x[-1] - unique_x[0] < 0.25 * width:
            return False

        rows = np.asarray([np.median(points_y[points_x == x]) for x in unique_x])
        normalized_t = (unique_x - unique_x[0]) / (unique_x[-1] - unique_x[0])
        curve_y = np.interp(normalized_t * 4.0, np.arange(5), expected_values)
        design = np.column_stack((curve_y, np.ones_like(curve_y)))
        scale, offset = np.linalg.lstsq(design, rows, rcond=None)[0]
        prediction = scale * curve_y + offset
        rmse = np.sqrt(np.mean((rows - prediction) ** 2))
        rendered_range = abs(scale) * np.ptp(expected_values)
        return rendered_range >= 0.20 * height and rmse <= max(4.0, 0.015 * height)

    structure = np.ones((3, 3), dtype=bool)
    for color in candidates:
        original = np.all(rgb == color, axis=2)
        # Dilation reconnects solid line-core pixels separated by anti-aliasing.
        labels, count = ndimage.label(ndimage.binary_dilation(original, structure=structure), structure=structure)
        for label_id in range(1, count + 1):
            component = labels == label_id
            ys, xs = np.nonzero(original & component)
            if matches(ys, xs):
                return True
    return False


def test_stability_plot_exists_and_contains_euler_trajectory():
    plot_path = "/home/user/stability_plot.png"
    assert os.path.isfile(plot_path), f"File {plot_path} does not exist."
    with open(plot_path, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", f"File {plot_path} is not a valid PNG file."

    import matplotlib.image as mpimg
    image = mpimg.imread(plot_path)
    assert image.ndim == 3 and image.shape[2] in (3, 4), "PNG must be a color image."
    assert image.shape[0] >= 150 and image.shape[1] >= 200, "Plot image is unreasonably small."
    rgb = image[:, :, :3]
    if np.issubdtype(rgb.dtype, np.floating):
        rgb = np.clip(np.rint(rgb * 255.0), 0, 255).astype(np.uint8)
    else:
        rgb = rgb.astype(np.uint8)
    assert np.ptp(rgb.astype(np.int16)) > 20, "Plot image appears blank."
    assert image_contains_euler_curve(rgb, expected_euler_y1()), \
        "Plot does not contain the expected dt=25 forward-Euler trajectory for y1."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_outputs.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
