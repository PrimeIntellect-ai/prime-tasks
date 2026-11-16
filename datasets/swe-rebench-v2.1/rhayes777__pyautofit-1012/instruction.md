Concise `model.info` for Models with lists of priors
In PyAutoLens, we often compose a model where a galaxy is made of 90 Gaussian's:

```
    analysis = al.AnalysisImaging(
        dataset=dataset,
        adapt_images=source_pix_results[0].adapt_images_from()
    )

    centre_0 = af.UniformPrior(lower_limit=-0.1, upper_limit=0.1)
    centre_1 = af.UniformPrior(lower_limit=-0.1, upper_limit=0.1)

    total_gaussians = 30
    gaussian_per_basis = 3

    log10_sigma_list = np.linspace(-2, np.log10(mask_radius), total_gaussians)

    bulge_gaussian_list = []

    for j in range(gaussian_per_basis):

        gaussian_list = af.Collection(af.Model(al.lp_linear.Gaussian) for _ in range(total_gaussians))

        for i, gaussian in enumerate(gaussian_list):
            gaussian.centre.centre_0 = centre_0
            gaussian.centre.centre_1 = centre_1
            gaussian.ell_comps = gaussian_list[0].ell_comps
            gaussian.sigma = 10 ** log10_sigma_list[i]

        bulge_gaussian_list += gaussian_list

    lens_bulge = af.Model(
        al.lp_basis.Basis,
        light_profile_list=bulge_gaussian_list,
    )
```

The `model.info` file of this model is... large:

```
Total Free Parameters = 12

model                                                                           Collection (N=12)
    galaxies                                                                    Collection (N=12)
        lens                                                                    Galaxy (N=12)
            bulge                                                               Basis (N=8)
                light_profile_list                                              Collection (N=8)
                    0                                                           Gaussian (N=4)
                    1                                                           Gaussian (N=4)
                    2                                                           Gaussian (N=4)
                    3                                                           Gaussian (N=4)
                    4                                                           Gaussian (N=4)
                    5                                                           Gaussian (N=4)
                    6                                                           Gaussian (N=4)
                    7                                                           Gaussian (N=4)
                    8                                                           Gaussian (N=4)
                    9                                                           Gaussian (N=4)
                    10                                                          Gaussian (N=4)
                    11                                                          Gaussian (N=4)
                    12                                                          Gaussian (N=4)
                    13                                                          Gaussian (N=4)
                    14                                                          Gaussian (N=4)
                    15                                                          Gaussian (N=4)
                    16                                                          Gaussian (N=4)
                    17                                                          Gaussian (N=4)
                    18                                                          Gaussian (N=4)
                    19                                                          Gaussian (N=4)
                    20                                                          Gaussian (N=4)
                    21                                                          Gaussian (N=4)
                    22                                                          Gaussian (N=4)
                    23                                                          Gaussian (N=4)
                    24                                                          Gaussian (N=4)
                    25                                                          Gaussian (N=4)
                    26                                                          Gaussian (N=4)
                    27                                                          Gaussian (N=4)
                    28                                                          Gaussian (N=4)
                    29                                                          Gaussian (N=4)
                    30                                                          Gaussian (N=4)
                    31                                                          Gaussian (N=4)
                    32                                                          Gaussian (N=4)
                    33                                                          Gaussian (N=4)
                    34                                                          Gaussian (N=4)
                    35                                                          Gaussian (N=4)
                    36                                                          Gaussian (N=4)
                    37                                                          Gaussian (N=4)
                    38                                                          Gaussian (N=4)
                    39                                                          Gaussian (N=4)
                    40                                                          Gaussian (N=4)
                    41                                                          Gaussian (N=4)
                    42                                                          Gaussian (N=4)
                    43                                                          Gaussian (N=4)
                    44                                                          Gaussian (N=4)
                    45                                                          Gaussian (N=4)
                    46                                                          Gaussian (N=4)
                    47                                                          Gaussian (N=4)
                    48                                                          Gaussian (N=4)
                    49                                                          Gaussian (N=4)
                    50                                                          Gaussian (N=4)
                    51                                                          Gaussian (N=4)
                    52                                                          Gaussian (N=4)
                    53                                                          Gaussian (N=4)
                    54                                                          Gaussian (N=4)
                    55                                                          Gaussian (N=4)
                    56                                                          Gaussian (N=4)
                    57                                                          Gaussian (N=4)
                    58                                                          Gaussian (N=4)
                    59                                                          Gaussian (N=4)
                    60                                                          Gaussian (N=4)
                    61                                                          Gaussian (N=4)
                    62                                                          Gaussian (N=4)
                    63                                                          Gaussian (N=4)
                    64                                                          Gaussian (N=4)
                    65                                                          Gaussian (N=4)
                    66                                                          Gaussian (N=4)
                    67                                                          Gaussian (N=4)
                    68                                                          Gaussian (N=4)
                    69                                                          Gaussian (N=4)
                    70                                                          Gaussian (N=4)
                    71                                                          Gaussian (N=4)
                    72                                                          Gaussian (N=4)
                    73                                                          Gaussian (N=4)
                    74                                                          Gaussian (N=4)
                    75                                                          Gaussian (N=4)
                    76                                                          Gaussian (N=4)
                    77                                                          Gaussian (N=4)
                    78                                                          Gaussian (N=4)
                    79                                                          Gaussian (N=4)
                    80                                                          Gaussian (N=4)
                    81                                                          Gaussian (N=4)
                    82                                                          Gaussian (N=4)
                    83                                                          Gaussian (N=4)
                    84                                                          Gaussian (N=4)
                    85                                                          Gaussian (N=4)
                    86                                                          Gaussian (N=4)
                    87                                                          Gaussian (N=4)
                    88                                                          Gaussian (N=4)
                    89                                                          Gaussian (N=4)
            point                                                               Basis (N=4)
                light_profile_list                                              Collection (N=4)
                    0                                                           Gaussian (N=4)
                    1                                                           Gaussian (N=4)
                    2                                                           Gaussian (N=4)
                    3                                                           Gaussian (N=4)
                    4                                                           Gaussian (N=4)
                    5                                                           Gaussian (N=4)
                    6                                                           Gaussian (N=4)
                    7                                                           Gaussian (N=4)
                    8                                                           Gaussian (N=4)
                    9                                                           Gaussian (N=4)
            mass                                                                Isothermal (N=0)
            shear                                                               ExternalShear (N=0)
        source                                                                  Galaxy (N=0)
            pixelization                                                        Pixelization (N=0)
                regularization                                                  AdaptiveBrightness (N=0)
                image_mesh                                                      Hilbert (N=0)

galaxies
    lens
        redshift                                                                0.44
        bulge
            light_profile_list
                0
                    centre
                        centre_0                                                UniformPrior [425], lower_limit = -0.1, upper_limit = 0.1
                        centre_1                                                UniformPrior [426], lower_limit = -0.1, upper_limit = 0.1
                    ell_comps
                        ell_comps_0                                             GaussianPrior [429], mean = 0.0, sigma = 0.3
                        ell_comps_1                                             GaussianPrior [430], mean = 0.0, sigma = 0.3
                    sigma                                                       0.01
                1
                    centre
                        centre_0                                                UniformPrior [425], lower_limit = -0.1, upper_limit = 0.1
                        centre_1                                                UniformPrior [426], lower_limit = -0.1, upper_limit = 0.1
                    ell_comps
                        ell_comps_0                                             GaussianPrior [429], mean = 0.0, sigma = 0.3
                        ell_comps_1                                             GaussianPrior [430], mean = 0.0, sigma = 0.3
                    sigma                                                       0.012294934136946248
                2
                    centre
                        centre_0                                                UniformPrior [425], lower_limit = -0.1, upper_limit = 0.1
                        centre_1                                                UniformPrior [426], lower_limit = -0.1, upper_limit = 0.1
                    ell_comps
                        ell_comps_0                                             GaussianPrior [429], mean = 0.0, sigma = 0.3
                        ell_comps_1                                             GaussianPrior [430], mean = 0.0, sigma = 0.3
                    sigma                                                       0.01511654054318462
                3
                    centre
                        centre_0                                                UniformPrior [425], lower_limit = -0.1, upper_limit = 0.1
                        centre_1                                                UniformPrior [426], lower_limit = -0.1, upper_limit = 0.1
                    ell_comps
                        ell_comps_0                                             GaussianPrior [429], mean = 0.0, sigma = 0.3
                        ell_comps_1                                             GaussianPrior [430], mean = 0.0, sigma = 0.3
                    sigma                                                       0.018585687035693257
                4
                    centre
                        centre_0                                                UniformPrior [425], lower_limit = -0.1, upper_limit = 0.1
                        centre_1                                                UniformPrior [426], lower_limit = -0.1, upper_limit = 0.1
                    ell_comps
                        ell_comps_0                                             GaussianPrior [429], mean = 0.0, sigma = 0.3
                        ell_comps_1                                             GaussianPrior [430], mean = 0.0, sigma = 0.3
                    sigma                                                       0.022850979799374435
                5
                    centre
                        centre_0                                                UniformPrior [425], lower_limit = -0.1, upper_limit = 0.1
                        centre_1                                                UniformPrior [426], lower_limit = -0.1, upper_limit = 0.1
                    ell_comps
                        ell_comps_0                                             GaussianPrior [429], mean = 0.0, sigma = 0.3
                        ell_comps_1                                             GaussianPrior [430], mean = 0.0, sigma = 0.3
                    sigma                                                       0.02809512915979979
                6
                    centre
                        centre_0                                                UniformPrior [425], lower_limit = -0.1, upper_limit = 0.1
                        centre_1                                                UniformPrior [426], lower_limit = -0.1, upper_limit = 0.1
                    ell_comps
                        ell_comps_0                                             GaussianPrior [429], mean = 0.0, sigma = 0.3
                        ell_comps_1                                             GaussianPrior [430], mean = 0.0, sigma = 0.3
                    sigma                                                       0.03454277625887364
                7
                    centre
                        centre_0                                                UniformPrior [425], lower_limit = -0.1, upper_limit = 0.1
                        centre_1                                                UniformPrior [426], lower_limit = -0.1, upper_limit = 0.1
                    ell_comps
                        ell_comps_0                                             GaussianPrior [429], mean = 0.0, sigma = 0.3
                        ell_comps_1                                             GaussianPrior [430], mean = 0.0, sigma = 0.3
                    sigma                                                       0.04247011590101218
                8
                    centre
                        centre_0                                                UniformPrior [425], lower_limit = -0.1, upper_limit = 0.1
                        centre_1                                                UniformPrior [426], lower_limit = -0.1, upper_limit = 0.1
                    ell_comps
                        ell_comps_0                                             GaussianPrior [429], mean = 0.0, sigma = 0.3
                        ell_comps_1                                             GaussianPrior [430], mean = 0.0, sigma = 0.3
                    sigma                                                       0.05221672777914186
                9
                    centre
                        centre_0                                                UniformPrior [425], lower_limit = -0.1, upper_limit = 0.1
                        centre_1                                                UniformPrior [426], lower_limit = -0.1, upper_limit = 0.1
                    ell_comps
                        ell_comps_0                                             GaussianPrior [429], mean = 0.0, sigma = 0.3
                        ell_comps_1                                             GaussianPrior [430], mean = 0.0, sigma = 0.3
                    sigma                                                       0.06420012288914004
                10
                    centre
                        centre_0                                                UniformPrior [425], lower_limit = -0.1, upper_limit = 0.1
                        centre_1                                                UniformPrior [426], lower_limit = -0.1, upper_limit = 0.1
                    ell_comps
                        ell_comps_0                                             GaussianPrior [429], mean = 0.0, sigma = 0.3
                        ell_comps_1                                             GaussianPrior [430], mean = 0.0, sigma = 0.3
                    sigma                                                       0.07893362825058325

        ....and so on ...


        mass
            centre                                                              (0.00601884753478887, 0.023999143834638678)
            ell_comps                                                           (0.16939516274352906, 0.0024119266740726814)
            einstein_radius                                                     1.1677486883648802
            slope                                                               2.0
            core_radius                                                         0.0
        shear
            centre                                                              (0.0, 0.0)
            ell_comps                                                           (0.0, 0.0)
            gamma_1                                                             -0.02979114689616666
            gamma_2                                                             -0.0030780392697618564
    source
        redshift                                                                1.192
        pixelization
            regularization
                inner_coefficient                                               0.0010924117924697946
                outer_coefficient                                               92.20305832737559
                signal_scale                                                    0.03604121120465
            image_mesh
                pixels                                                          1000
                weight_floor                                                    7.284022314666776e-05
                weight_power                                                    2.62031156076238
```

The question is, how do we make this more concise?

There is repetition in the list of model component types:

```
                light_profile_list                                              Collection (N=8)
                    0                                                           Gaussian (N=4)
                    1                                                           Gaussian (N=4)
                    2                                                           Gaussian (N=4)
                    3                                                           Gaussian (N=4)
                     ...
```

We can condense this as follows:

```
                light_profile_list                                              Collection (N=8)
                    0 -89                                                      Gaussian (N=4)
```


There is constant repetition of priors, for example all `Gaussian` objects from 0 to 29 have the same priors:

```        bulge
            light_profile_list
                0
                    centre
                        centre_0                                                UniformPrior [425], lower_limit = -0.1, upper_limit = 0.1
                        centre_1                                                UniformPrior [426], lower_limit = -0.1, upper_limit = 0.1
                    ell_comps
                        ell_comps_0                                             GaussianPrior [429], mean = 0.0, sigma = 0.3
                        ell_comps_1                                             GaussianPrior [430], mean = 0.0, sigma = 0.3
                    sigma                                                       0.01
                1
                    centre
                        centre_0                                                UniformPrior [425], lower_limit = -0.1, upper_limit = 0.1
                        centre_1                                                UniformPrior [426], lower_limit = -0.1, upper_limit = 0.1
                    ell_comps
                        ell_comps_0                                             GaussianPrior [429], mean = 0.0, sigma = 0.3
                        ell_comps_1                                             GaussianPrior [430], mean = 0.0, sigma = 0.3
                    sigma                                                       0.012294934136946248
                2
                    centre
                        centre_0                                                UniformPrior [425], lower_limit = -0.1, upper_limit = 0.1
                        centre_1                                                UniformPrior [426], lower_limit = -0.1, upper_limit = 0.1
                    ell_comps
                        ell_comps_0                                             GaussianPrior [429], mean = 0.0, sigma = 0.3
                        ell_comps_1                                             GaussianPrior [430], mean = 0.0, sigma = 0.3
                    sigma                                                       0.01511654054318462
                3
                    centre
                        centre_0                                                UniformPrior [425], lower_limit = -0.1, upper_limit = 0.1
                        centre_1                                                UniformPrior [426], lower_limit = -0.1, upper_limit = 0.1
                    ell_comps
                        ell_comps_0                                             GaussianPrior [429], mean = 0.0, sigma = 0.3
                        ell_comps_1                                             GaussianPrior [430], mean = 0.0, sigma = 0.3
                    sigma                                                       0.018585687035693257
```

We could identify all model components with overlapping priors and condence as follows:

```        bulge
            light_profile_list
                0-29
                    centre
                        centre_0                                                UniformPrior [425], lower_limit = -0.1, upper_limit = 0.1
                        centre_1                                                UniformPrior [426], lower_limit = -0.1, upper_limit = 0.1
                    ell_comps
                        ell_comps_0                                             GaussianPrior [429], mean = 0.0, sigma = 0.3
                        ell_comps_1                                             GaussianPrior [430], mean = 0.0, sigma = 0.3
                0
                    sigma                                                       0.01
                1
                    sigma                                                       0.012294934136946248
                2
                    sigma                                                       0.01511654054318462
                3
                    sigma                                                       0.018585687035693257
```

I suspect this will be useful for graph visualization...

### Additional contract requirements

Add a public function `integers_representative_key(integers: List[int]) -> str` in the module `autofit.mapper.prior_model.representative`. It accepts a list of integers in any order and returns a concise string representation of them: consecutive integers are written as `start - end`, and distinct parts are separated by commas. For example `[1, 2, 3, 8, 9, 10]` becomes `"1 - 3, 8 - 10"`, `[1, 10]` becomes `"1, 10"`, and `[1]` becomes `"1"`.
