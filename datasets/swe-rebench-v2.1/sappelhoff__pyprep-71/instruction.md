removeTrend produces different values in PyPREP than MATLAB PREP
Splitting this off from #49 to keep things organized. Basically, the removeTrend function (which essentially just runs a highpass filter to remove frequencies below 1 Hz) produces different values in PyPREP's implementation (by default, a wrapper around `mne.filter.filter_data`) than in MATLAB PREP's implementation (by default, a wrapper around EEGLAB's `pop_eegfiltnew`).

For comparison I loaded the same .set file into both EEGLAB and MNE, applied `removeTrend` to both, then re-saved the .set from EEGLAB so I could load it into MNE and compare. The PSD plots for both look identical to me, but the numeric values themselves via `raw._data` look quite different:


<details>
  <summary>Comparisons of MATLAB and PyPREP values (click to unhide)</summary>

First sample of first 10 channels in MATLAB PREP before trend removal:
```
signal.data(:, 1)

ans =

   1.0e+04 *

   -0.3335
    1.0037
   -0.3581
   -0.1795
    0.9913
   -0.7414
   -0.7198
   -0.5665
    0.5557
   -1.2237
```

 First sample of first 10 channels in MATLAB PREP after trend removal:
```
signal2.data(:, 1)

ans =

   -3.7068
   -4.8012
   -0.8008
   -2.5809
   -1.5205
    0.1093
    1.9928
   -4.6906
  -10.2859
    1.6814
```

First sample of first 10 channels in PyPREP before trend removal:
```
raw_copy._data[:10, 0]
array([-0.00333541,  0.01003745, -0.00358109, -0.00179516,  0.00991251,
       -0.00741443, -0.00719762, -0.00566537,  0.00555661, -0.01223686])
```

First sample of first 10 channels in PyPREP after trend removal:
```
raw_filtered._data[:10, 0]
array([-4.11658012e-19, -1.79973325e-18,  6.98802181e-19,  2.89261751e-19,
        2.50128829e-18, -9.28348110e-19,  7.57247455e-19,  3.55753838e-19,
        3.82858892e-19, -7.01343280e-19])
```
</details>

Since the plots look the same the differences might not practically matter all that much, but if we want to be able to do formal (or informal) 1:1 comparisons of PyPREP results to MatPREP, having identical results from this function would be helpful, especially since this always happens before any of the NoisyChannels operations.

### Additional contract requirements

For high-pass detrending, `removeTrend` must be capable of producing numerical results compatible with MATLAB PREP for the same signal and filter settings. This compatibility is opt-in through the public `matlab_strict=True` argument; callers who do not opt in retain the default behavior.
