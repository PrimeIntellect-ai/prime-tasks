Graphical Model 1: `model.info` and `model.graph`
The following example compares a run using analysis summing and graph:

https://github.com/Jammy2211/autolens_workspace_test/blob/main/model_graph/task_1_model_info.py

You can run it fast by using the `export PYAUTOFIT_TEST_MODE=1` environment variable.

For analysis summing, we get the following `model.info` file:

```
Total Free Parameters = 26

model                                                                           Collection (N=26)
    0 - 1                                                                       Collection (N=26)
        galaxies                                                                Collection (N=26)
            lens                                                                Galaxy (N=19)
                bulge                                                           Basis (N=6)
                    profile_list                                                Collection (N=6)
                        0 - 59                                                  Gaussian (N=4)
                disk                                                            Exponential (N=6)
                mass                                                            Isothermal (N=5)
                shear                                                           ExternalShear (N=2)
            source                                                              Galaxy (N=7)
                bulge                                                           Sersic (N=7)
        dataset_model                                                           DatasetModel (N=0)

0 - 1
    dataset_model
        background_sky_level                                                    0.0
        grid_offset
            grid_offset_0 - grid_offset_1                                       0.0
    galaxies
        lens
            redshift                                                            0.5
            disk
                intensity                                                       LogUniformPrior [557], lower_limit = 0.99999, upper_limit = 1.0000001
                effective_radius                                                UniformPrior [558], lower_limit = 0.99999, upper_limit = 1.000001
                centre
                    centre_0                                                    GaussianPrior [553], mean = 0.0, sigma = 0.0001
                    centre_1                                                    GaussianPrior [554], mean = 0.0, sigma = 0.0001
                ell_comps
                    ell_comps_0                                                 UniformPrior [555], lower_limit = -0.001, upper_limit = 0.001
                    ell_comps_1                                                 UniformPrior [556], lower_limit = -0.001, upper_limit = 0.001
            mass
                einstein_radius                                                 UniformPrior [563], lower_limit = 1.5999, upper_limit = 1.6001
                centre
                    centre_0                                                    GaussianPrior [559], mean = 0.0, sigma = 0.001
                    centre_1                                                    GaussianPrior [560], mean = 0.0, sigma = 0.001
                ell_comps
                    ell_comps_0                                                 UniformPrior [561], lower_limit = -0.001, upper_limit = 0.001
                    ell_comps_1                                                 UniformPrior [562], lower_limit = -0.001, upper_limit = 0.001
            shear
                gamma_1                                                         UniformPrior [564], lower_limit = -1e-05, upper_limit = 1e-05
                gamma_2                                                         UniformPrior [565], lower_limit = -1e-05, upper_limit = 1e-05
            bulge
                profile_list
                    0 - 59
                        centre
                            centre_0                                            GaussianPrior [99], mean = 0.0, sigma = 0.1
                            centre_1                                            GaussianPrior [100], mean = 0.0, sigma = 0.1
                    0 - 29
                        ell_comps
                            ell_comps_0                                         UniformPrior [103], lower_limit = -0.001, upper_limit = 0.001
                            ell_comps_1                                         UniformPrior [104], lower_limit = -0.001, upper_limit = 0.001
                    0
                        sigma                                                   0.01
                    1
                        sigma                                                   0.012173570475023513
                    2
                        sigma                                                   0.01481958181103642
                    3
                        sigma                                                   0.018040722358702844
                    4
                        sigma                                                   0.02196200050540015
                    5
                        sigma                                                   0.026735596092499075
                    6
                        sigma                                                   0.03254676632238009
                    7
                        sigma                                                   0.03962103535596159
                    8
                        sigma                                                   0.04823294661991968
                    9
                        sigma                                                   0.05871671748956393
                    10
                        sigma                                                   0.07147920984212522
                    11
                        sigma                                                   0.08701571985121061
                    12
                        sigma                                                   0.1059291998043615
                    13
                        sigma                                                   0.12895365791812416
                    14
                        sigma                                                   0.15698264426783584
                    15
                        sigma                                                   0.19110392833500456
                    16
                        sigma                                                   0.23264171396400207
                    17
                        sigma                                                   0.2832080300371041
                    18
                        sigma                                                   0.3447652912749263
                    19
                        sigma                                                   0.4197024570677324
                    20
                        sigma                                                   0.510927743965457
                    21
                        sigma                                                   0.6219814898808265
                    22
                        sigma                                                   0.7571735501224365
                    23
                        sigma                                                   0.9217505574239229
                    24
                        sigma                                                   1.122099537119234
                    25
                        sigma                                                   1.3659957795112256
                    26
                        sigma                                                   1.6629045890464587
                    27
                        sigma                                                   2.0243486207997075
                    28
                        sigma                                                   2.464355060132189
                    29
                        sigma                                                   3.0
                    30 - 59
                        ell_comps
                            ell_comps_0                                         UniformPrior [253], lower_limit = -0.001, upper_limit = 0.001
                            ell_comps_1                                         UniformPrior [254], lower_limit = -0.001, upper_limit = 0.001
                    30
                        sigma                                                   0.01
                    31
                        sigma                                                   0.012173570475023513
                    32
                        sigma                                                   0.01481958181103642
                    33
                        sigma                                                   0.018040722358702844
                    34
                        sigma                                                   0.02196200050540015
                    35
                        sigma                                                   0.026735596092499075
                    36
                        sigma                                                   0.03254676632238009
                    37
                        sigma                                                   0.03962103535596159
                    38
                        sigma                                                   0.04823294661991968
                    39
                        sigma                                                   0.05871671748956393
                    40
                        sigma                                                   0.07147920984212522
                    41
                        sigma                                                   0.08701571985121061
                    42
                        sigma                                                   0.1059291998043615
                    43
                        sigma                                                   0.12895365791812416
                    44
                        sigma                                                   0.15698264426783584
                    45
                        sigma                                                   0.19110392833500456
                    46
                        sigma                                                   0.23264171396400207
                    47
                        sigma                                                   0.2832080300371041
                    48
                        sigma                                                   0.3447652912749263
                    49
                        sigma                                                   0.4197024570677324
                    50
                        sigma                                                   0.510927743965457
                    51
                        sigma                                                   0.6219814898808265
                    52
                        sigma                                                   0.7571735501224365
                    53
                        sigma                                                   0.9217505574239229
                    54
                        sigma                                                   1.122099537119234
                    55
                        sigma                                                   1.3659957795112256
                    56
                        sigma                                                   1.6629045890464587
                    57
                        sigma                                                   2.0243486207997075
                    58
                        sigma                                                   2.464355060132189
                    59
                        sigma                                                   3.0
        source
            redshift                                                            1.0
            bulge
                intensity                                                       LogUniformPrior [570], lower_limit = 0.99999, upper_limit = 1.0000001
                effective_radius                                                UniformPrior [571], lower_limit = 0.99999, upper_limit = 1.000001
                sersic_index                                                    UniformPrior [572], lower_limit = 1.9999, upper_limit = 2.0001
                centre
                    centre_0                                                    GaussianPrior [566], mean = 0.0, sigma = 0.0001
                    centre_1                                                    GaussianPrior [567], mean = 0.0, sigma = 0.0001
                ell_comps
                    ell_comps_0                                                 UniformPrior [568], lower_limit = -0.001, upper_limit = 0.001
                    ell_comps_1                                                 UniformPrior [569], lower_limit = -0.001, upper_limit = 0.001
```

For graphical models, we get this:

```
PriorFactors

PriorFactor0 (AnalysisFactor0.galaxies.lens.bulge.profile_list.59.ell_comps.ell_comps_1, AnalysisFactor1.galaxies.lens.bulge.profile_list.59.ell_comps.ell_comps_1) UniformPrior [254], lower_limit = -0.001, upper_limit = 0.001
PriorFactor1 (AnalysisFactor0.galaxies.lens.bulge.profile_list.59.ell_comps.ell_comps_0, AnalysisFactor1.galaxies.lens.bulge.profile_list.59.ell_comps.ell_comps_0) UniformPrior [253], lower_limit = -0.001, upper_limit = 0.001
PriorFactor2 (AnalysisFactor0.galaxies.lens.bulge.profile_list.29.ell_comps.ell_comps_1, AnalysisFactor1.galaxies.lens.bulge.profile_list.29.ell_comps.ell_comps_1) UniformPrior [104], lower_limit = -0.001, upper_limit = 0.001
PriorFactor3 (AnalysisFactor0.galaxies.lens.bulge.profile_list.29.ell_comps.ell_comps_0, AnalysisFactor1.galaxies.lens.bulge.profile_list.29.ell_comps.ell_comps_0) UniformPrior [103], lower_limit = -0.001, upper_limit = 0.001
PriorFactor4 (AnalysisFactor0.galaxies.lens.bulge.profile_list.59.centre.centre_1, AnalysisFactor1.galaxies.lens.bulge.profile_list.59.centre.centre_1) GaussianPrior [100], mean = 0.0, sigma = 0.1
PriorFactor5 (AnalysisFactor0.galaxies.lens.bulge.profile_list.59.centre.centre_0, AnalysisFactor1.galaxies.lens.bulge.profile_list.59.centre.centre_0) GaussianPrior [99], mean = 0.0, sigma = 0.1
PriorFactor6 (AnalysisFactor0.galaxies.source.bulge.sersic_index, AnalysisFactor1.galaxies.source.bulge.sersic_index) UniformPrior [572], lower_limit = 1.9999, upper_limit = 2.0001
PriorFactor7 (AnalysisFactor0.galaxies.source.bulge.effective_radius, AnalysisFactor1.galaxies.source.bulge.effective_radius) UniformPrior [571], lower_limit = 0.99999, upper_limit = 1.000001
PriorFactor8 (AnalysisFactor0.galaxies.source.bulge.intensity, AnalysisFactor1.galaxies.source.bulge.intensity) LogUniformPrior [570], lower_limit = 0.99999, upper_limit = 1.0000001
PriorFactor9 (AnalysisFactor0.galaxies.source.bulge.ell_comps.ell_comps_1, AnalysisFactor1.galaxies.source.bulge.ell_comps.ell_comps_1) UniformPrior [569], lower_limit = -0.001, upper_limit = 0.001
PriorFactor10 (AnalysisFactor0.galaxies.source.bulge.ell_comps.ell_comps_0, AnalysisFactor1.galaxies.source.bulge.ell_comps.ell_comps_0) UniformPrior [568], lower_limit = -0.001, upper_limit = 0.001
PriorFactor11 (AnalysisFactor0.galaxies.source.bulge.centre.centre_1, AnalysisFactor1.galaxies.source.bulge.centre.centre_1) GaussianPrior [567], mean = 0.0, sigma = 0.0001
PriorFactor12 (AnalysisFactor0.galaxies.source.bulge.centre.centre_0, AnalysisFactor1.galaxies.source.bulge.centre.centre_0) GaussianPrior [566], mean = 0.0, sigma = 0.0001
PriorFactor13 (AnalysisFactor0.galaxies.lens.shear.gamma_2, AnalysisFactor1.galaxies.lens.shear.gamma_2) UniformPrior [565], lower_limit = -1e-05, upper_limit = 1e-05
PriorFactor14 (AnalysisFactor0.galaxies.lens.shear.gamma_1, AnalysisFactor1.galaxies.lens.shear.gamma_1) UniformPrior [564], lower_limit = -1e-05, upper_limit = 1e-05
PriorFactor15 (AnalysisFactor0.galaxies.lens.mass.einstein_radius, AnalysisFactor1.galaxies.lens.mass.einstein_radius) UniformPrior [563], lower_limit = 1.5999, upper_limit = 1.6001
PriorFactor16 (AnalysisFactor0.galaxies.lens.mass.ell_comps.ell_comps_1, AnalysisFactor1.galaxies.lens.mass.ell_comps.ell_comps_1) UniformPrior [562], lower_limit = -0.001, upper_limit = 0.001
PriorFactor17 (AnalysisFactor0.galaxies.lens.mass.ell_comps.ell_comps_0, AnalysisFactor1.galaxies.lens.mass.ell_comps.ell_comps_0) UniformPrior [561], lower_limit = -0.001, upper_limit = 0.001
PriorFactor18 (AnalysisFactor0.galaxies.lens.mass.centre.centre_1, AnalysisFactor1.galaxies.lens.mass.centre.centre_1) GaussianPrior [560], mean = 0.0, sigma = 0.001
PriorFactor19 (AnalysisFactor0.galaxies.lens.mass.centre.centre_0, AnalysisFactor1.galaxies.lens.mass.centre.centre_0) GaussianPrior [559], mean = 0.0, sigma = 0.001
PriorFactor20 (AnalysisFactor0.galaxies.lens.disk.effective_radius, AnalysisFactor1.galaxies.lens.disk.effective_radius) UniformPrior [558], lower_limit = 0.99999, upper_limit = 1.000001
PriorFactor21 (AnalysisFactor0.galaxies.lens.disk.intensity, AnalysisFactor1.galaxies.lens.disk.intensity) LogUniformPrior [557], lower_limit = 0.99999, upper_limit = 1.0000001
PriorFactor22 (AnalysisFactor0.galaxies.lens.disk.ell_comps.ell_comps_1, AnalysisFactor1.galaxies.lens.disk.ell_comps.ell_comps_1) UniformPrior [556], lower_limit = -0.001, upper_limit = 0.001
PriorFactor23 (AnalysisFactor0.galaxies.lens.disk.ell_comps.ell_comps_0, AnalysisFactor1.galaxies.lens.disk.ell_comps.ell_comps_0) UniformPrior [555], lower_limit = -0.001, upper_limit = 0.001
PriorFactor24 (AnalysisFactor0.galaxies.lens.disk.centre.centre_1, AnalysisFactor1.galaxies.lens.disk.centre.centre_1) GaussianPrior [554], mean = 0.0, sigma = 0.0001
PriorFactor25 (AnalysisFactor0.galaxies.lens.disk.centre.centre_0, AnalysisFactor1.galaxies.lens.disk.centre.centre_0) GaussianPrior [553], mean = 0.0, sigma = 0.0001

AnalysisFactors

AnalysisFactor0

galaxies
    lens
        bulge
            profile_list
                0
                    centre
                        centre_0 (AnalysisFactor1.galaxies.lens.bulge.profile_list.59.centre.centre_0, PriorFactor5) GaussianPrior [99], mean = 0.0, sigma = 0.1
                        centre_1 (AnalysisFactor1.galaxies.lens.bulge.profile_list.59.centre.centre_1, PriorFactor4) GaussianPrior [100], mean = 0.0, sigma = 0.1
                    ell_comps
                        ell_comps_0 (AnalysisFactor1.galaxies.lens.bulge.profile_list.29.ell_comps.ell_comps_0, PriorFactor3) UniformPrior [103], lower_limit = -0.001, upper_limit = 0.001
                        ell_comps_1 (AnalysisFactor1.galaxies.lens.bulge.profile_list.29.ell_comps.ell_comps_1, PriorFactor2) UniformPrior [104], lower_limit = -0.001, upper_limit = 0.001
                1
                    centre
                        centre_0 (AnalysisFactor1.galaxies.lens.bulge.profile_list.59.centre.centre_0, PriorFactor5) GaussianPrior [99], mean = 0.0, sigma = 0.1
                        centre_1 (AnalysisFactor1.galaxies.lens.bulge.profile_list.59.centre.centre_1, PriorFactor4) GaussianPrior [100], mean = 0.0, sigma = 0.1
                    ell_comps
                        ell_comps_0 (AnalysisFactor1.galaxies.lens.bulge.profile_list.29.ell_comps.ell_comps_0, PriorFactor3) UniformPrior [103], lower_limit = -0.001, upper_limit = 0.001
                        ell_comps_1 (AnalysisFactor1.galaxies.lens.bulge.profile_list.29.ell_comps.ell_comps_1, PriorFactor2) UniformPrior [104], lower_limit = -0.001, upper_limit = 0.001
                2
...
```

However, for graphs `model.result` looks much closer to `model.info` of analysis summing:

```
Bayesian Evidence                                                               -107816562779.35780334
Maximum Log Likelihood                                                          -107816562774.75263977
Maximum Log Posterior                                                           -107816562769.27525330

model                                                                           GlobalPriorModel (N=26)
    0 - 1                                                                       Collection (N=26)
        galaxies                                                                Collection (N=26)
            lens                                                                Galaxy (N=19)
                bulge                                                           Basis (N=6)
                    profile_list                                                Collection (N=6)
                        0 - 59                                                  Gaussian (N=4)
                disk                                                            Exponential (N=6)
                mass                                                            Isothermal (N=5)
                shear                                                           ExternalShear (N=2)
            source                                                              Galaxy (N=7)
                bulge                                                           Sersic (N=7)
        dataset_model                                                           DatasetModel (N=0)

Maximum Log Likelihood Model:

0 - 1
    galaxies
        lens
            disk
                intensity                                                       1.000
                effective_radius                                                1.000
                centre
                    centre_0                                                    0.000
                    centre_1                                                    -0.000
                ell_comps
                    ell_comps_0                                                 -0.001
                    ell_comps_1                                                 0.001
            mass
                einstein_radius                                                 1.600
                centre
                    centre_0                                                    -0.000
                    centre_1                                                    0.000
                ell_comps
                    ell_comps_0                                                 -0.000
                    ell_comps_1                                                 -0.000
            shear
                gamma_1                                                         0.000
                gamma_2                                                         -0.000
            bulge
                profile_list
                    0 - 59
                        centre
                            centre_0                                            0.027
                            centre_1                                            0.082
                    0 - 29
                        ell_comps
                            ell_comps_0                                         0.001
                            ell_comps_1                                         0.001
                    30 - 59
                        ell_comps
                            ell_comps_0                                         0.000
                            ell_comps_1                                         0.001
        source
            bulge
                intensity                                                       1.000
                effective_radius                                                1.000
                sersic_index                                                    2.000
                centre
                    centre_0                                                    0.000
                    centre_1                                                    -0.000
                ell_comps
                    ell_comps_0                                                 -0.000
                    ell_comps_1                                                 -0.001

 WARNING: The samples have not converged enough to compute a PDF and model errors.
 The model below over estimates errors.



Summary (1.0 sigma limits):

0 - 1
    galaxies
        lens
            disk
                effective_radius - intensity                                    1.0000 (1.0000, 1.0000)
                centre
                    centre_0                                                    0.0001 (-0.0002, 0.0002)
                    centre_1                                                    -0.0001 (-0.0002, 0.0003)
                ell_comps
                    ell_comps_0                                                 -0.0006 (-0.0010, 0.0010)
                    ell_comps_1                                                 0.0006 (-0.0009, 0.0010)
            mass
                einstein_radius                                                 1.6001 (1.5999, 1.6001)
                centre
                    centre_0                                                    -0.0001 (-0.0036, 0.0030)
                    centre_1                                                    0.0004 (-0.0025, 0.0029)
                ell_comps
                    ell_comps_0                                                 -0.0005 (-0.0010, 0.0009)
                    ell_comps_1                                                 -0.0001 (-0.0010, 0.0010)
            shear
                gamma_1                                                         0.0000 (-0.0000, 0.0000)
                gamma_2                                                         -0.0000 (-0.0000, 0.0000)
            bulge
                profile_list
                    0 - 59
                        centre
                            centre_0                                            0.0275 (-0.2514, 0.2072)
                            centre_1                                            0.0822 (-0.2261, 0.2567)
                    0 - 29
                        ell_comps
                            ell_comps_0                                         0.0007 (-0.0010, 0.0010)
                            ell_comps_1                                         0.0006 (-0.0010, 0.0010)
                    30 - 59
                        ell_comps
                            ell_comps_0                                         0.0001 (-0.0010, 0.0010)
                            ell_comps_1                                         0.0008 (-0.0010, 0.0010)
        source
            bulge
                effective_radius - intensity                                    1.0000 (1.0000, 1.0000)
                sersic_index                                                    2.0000 (1.9999, 2.0001)
                centre
                    centre_0                                                    0.0002 (-0.0002, 0.0002)
                    centre_1                                                    -0.0000 (-0.0003, 0.0003)
                ell_comps
                    ell_comps_0                                                 -0.0002 (-0.0010, 0.0010)
                    ell_comps_1                                                 -0.0009 (-0.0010, 0.0010)

instances

0 - 1
    dataset_model
        background_sky_level
            value                                                               0.0
        grid_offset
            grid_offset_0 - grid_offset_1
                value                                                           0.0
    galaxies
        lens
            redshift
                value                                                           0.5
            bulge
                profile_list
                    0, 30
                        sigma
                            value                                               0.01
                    1, 31
                        sigma

```

**I therefore suspect that a graphcial model can output a `model.info` file in the format of analysis summing which much effort.**

Could you make it so that when a graphical model is fitted, it outputs both a `model.info` file (Which is identical the analysis summing one) and a `model.graph` file, which is the one it currently outputs.
