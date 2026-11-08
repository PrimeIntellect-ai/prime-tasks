In `Powerspectrum`, the calculation of rms and rms error are wrong
I could see two problems with the method `compute_rms` and the related `_rms_error`:

1. It just sums over the powers, without eliminating the white noise level

2. The error is always assumed in Leahy normalization!

### Additional contract requirements

`Powerspectrum.compute_rms(min_freq, max_freq, white_noise_offset=0.)` accepts an optional `white_noise_offset`, expressed in Leahy normalization. It subtracts that level's contribution over the selected frequency interval when calculating the fractional RMS. The same interface and behavior are available for `AveragedPowerspectrum`. With a zero offset, results for an otherwise identical periodogram must be consistent whether its powers use Leahy or fractional normalization.

The reported RMS uncertainty must also be consistent between Leahy and fractional normalization for an otherwise identical periodogram; it must account for the chosen normalization rather than treating fractional-normalized powers as Leahy-normalized.
