Batch inversion of transformation matrices
The following code should be correct and go to pytransform3d.trajectories. It is not tested though.

```python
def batch_invert_transform(A2Bs):
    """Invert transforms.

    Parameters
    ----------
    A2Bs : array-like, shape (..., 4, 4)
        Transforms from frames A to frames B

    Returns
    -------
    B2As : array-like, shape (..., 4, 4)
        Transforms from frames B to frames A
    """
    A2Bs = np.asarray(A2Bs)
    instances_shape = A2Bs.shape[:-2]
    B2As = np.empty_like(A2Bs)
    [HIDDEN]
    B2As[..., :3, :3] = A2Bs[..., :3, :3].transpose(list(range(A2Bs.ndim - 2)) + [A2Bs.ndim - 1, A2Bs.ndim - 2])
    [HIDDEN]
    B2As[..., 3, :3] = 0.0
    B2As[..., 3, 3] = 1.0
    return B2As
```

### Additional contract requirements

- Add a public function `invert_transforms(A2Bs)` in module `pytransform3d.trajectories`.
- It accepts an array-like of shape `(..., 4, 4)` containing homogeneous transformation matrices that map coordinates from frame A to frame B.
- It returns a NumPy ndarray of the same shape `(..., 4, 4)` containing the inverse transformations that map from frame B back to frame A.
- Any number of leading batch dimensions is supported and preserved, including scalar (0-dimensional), vector (1-dimensional) and higher-dimensional batches.
- Each returned matrix is the inverse of the corresponding input matrix, matching the single-matrix helper `invert_transform`.
