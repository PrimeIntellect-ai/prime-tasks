Bad channels by correlation differ between PyPREP and MATLAB PREP
In my recent comparison efforts, I noticed that the numbers of initial bad channels by correlation sometimes differed slightly between PyPREP and MATLAB PREP. Since this code doesn't involve any random number generation, it should always be consistent between runs and also between implementations.

Anyway, I did some digging with breakpoints and think I've figured it out. It has to do with [these lines here](https://github.com/sappelhoff/pyprep/blob/8476ea5c1f80c60e564ce8e4c2fca34464515b40/pyprep/find_noisy_channels.py#L320-L332):

```python
        for k in range(0, w_correlation):
            eeg_portion = np.transpose(np.squeeze(EEG_new_win[:, :, k]))
            data_portion = np.transpose(np.squeeze(data_win[:, :, k]))
            window_correlation = np.corrcoef(np.transpose(eeg_portion))
            abs_corr = np.abs(
                np.subtract(window_correlation, np.diag(np.diag(window_correlation)))
            )
            channel_correlation[k, :] = [HIDDEN]
            noiselevels[k, :] = np.divide(
                robust.mad(np.subtract(data_portion, eeg_portion), c=1),
                robust.mad(eeg_portion, c=1),
            )
            channel_deviations[k, :] = [HIDDEN]
```
Using the same input data, we see that `eeg_portion`, `data_portion`, `window_correlation`, `abs_corr`, and `noiselevels` are all identical between PyPREP and MatPREP, but `channel_correlation` and `channel_deviations` both differ.

The reason for this is that apparently [MATLAB's quantile functions work slightly differently than Numpy's and SciPy's](https://stackoverflow.com/a/58424860): instead of having quantiles be restricted to the range [0, 1], they get restricted to the range [0.5 / n, (n - 0.5) / n], with n being the number of samples passed to the quantile function. This is apparently equivalent to treating the provided values as a sample of an unknown population rather than a full population themselves. After hacking together some new `quantile` and `iqr` functions that account for this, the `channel_correlation` and `channel_deviations` data both match the MATLAB values!

Anyway, I'll put together a PR to address this, but I figure there should be a discussion of which quantile logic actually makes the most sense for this use-case. If Numpy's default logic is actually more reasonable/justifiable here, we can make the new quantile functions optional with a `match_matlab` flag  or parameter of some kind indicating strict adherence to the original PREP logic. If MATLAB's logic makes more sense, I'm assuming we should just fully replace `np.quantile` and `iqr` with their modified equivalents?

### Additional contract requirements

- Bad-channel detection by correlation and deviation must use MATLAB-compatible quantile and inter-quartile range behavior, so its results match MATLAB PREP rather than NumPy or SciPy defaults. The sample-size-dependent quantile positions must be restricted to \([0.5 / n, (n - 0.5) / n]\), where \(n\) is the number of samples used for the quantile.
- Add a public function `_mat_quantile(arr, q, axis=None)` in module `pyprep.utils`. It returns the MATLAB-compatible quantile of `arr` at quantile `q`, where `q` is between 0 and 1 inclusive. `axis` may be an integer, a tuple of integers, or `None`; when `axis` is `None` the quantile is computed over the flattened array.
- Add a public function `_mat_iqr(arr, axis=None)` in module `pyprep.utils`. It returns the inter-quartile range (75th percentile minus 25th percentile) of `arr` using the same MATLAB-compatible quantile adjustment. `axis` may be an integer, a tuple of integers, or `None`; when `axis` is `None` the IQR is computed over the flattened array.
