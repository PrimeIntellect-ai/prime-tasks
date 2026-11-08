Wrong sign in disp reconstruction
Hi there!

I'm attempting to create IRFs of a single SST using the `ctapipe 0.24.0` CLI.

After disp reconstruction, many point-source gamma-rays are well-reconstructed, but many are not, clustered in a ring around the true source direction. The resulting angular resolution is thus very poor.

I don't know how best to diagnose this. My first thoughts are that it maybe has something to do with sign reconstruction, or perhaps coordinate transformations in a dual-mirror telescope?

![Image](https://github.com/user-attachments/assets/ba016b8e-f5af-426c-baba-4709a8ff9f09)

![Image](https://github.com/user-attachments/assets/407de11d-5e96-4e5c-96fe-b4953f60bf62)

Here is my `train_disp_reconstructor.yaml`

```
TrainDispReconstructor:
  random_seed: 0
  n_events:

  CrossValidator:
    n_cross_validations: 5
    rng_seed: 1337

  DispReconstructor:
    n_jobs: -1

    norm_cls: RandomForestRegressor
    log_target: True
    sign_cls: RandomForestClassifier

    QualityQuery:
      quality_criteria:
        - ["enough intensity", "hillas_intensity > 50"]
        - ["Positive width", "hillas_width > 0"]
        - ["enough pixels", "morphology_n_pixels > 3"]
        - ["not clipped", "leakage_intensity_width_2 < 0.5"]

    FeatureGenerator:
      features:
        - ["area", "hillas_width * hillas_length"]

    features:
      - hillas_intensity
      - hillas_r
      - hillas_length
      - hillas_width
      - hillas_skewness
      - hillas_kurtosis
      - timing_slope
      - timing_deviation
      - leakage_intensity_width_1
      - leakage_intensity_width_2
      - leakage_pixels_width_1
      - leakage_pixels_width_2
      - concentration_cog
      - concentration_core
      - morphology_n_islands
      - morphology_n_large_islands
      - morphology_n_medium_islands
      - peak_time_std
      - peak_time_skewness
      - peak_time_kurtosis
      - intensity_max
      - intensity_mean
      - intensity_std
      - intensity_skewness
      - intensity_kurtosis
      - area
```
