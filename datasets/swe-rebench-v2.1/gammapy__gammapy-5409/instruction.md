Modify `MapAxis.downsample`
Modify `MapAxis.downsample` to have an option strict=False option which when set to True will simply put the remainder in the last bin
 https://github.com/gammapy/gammapy/pull/5007#discussion_r1455938626_

### Additional contract requirements

- `strict=False` permits leftover source bins and includes them in the final downsampled bin, retaining the original axis limits.
- `strict=True` raises `ValueError` when the number of source edge bins, or the number of source center nodes minus one, is not divisible by the downsampling factor.
- For divisible axes, strict and non-strict downsampling produce the same factor-based result.
