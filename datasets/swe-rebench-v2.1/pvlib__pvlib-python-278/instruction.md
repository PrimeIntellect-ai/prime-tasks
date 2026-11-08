calculate Linke turbidity factor from AOD, precip water and airmass
Given aerosol optical depth (AOD), Angstrom alpha and precipitable water (_AKA_ total column water vapor) calculate Linke turbidity factor using Molineaux (1998), Bird-Hulstrom (1980), Berk (1996) and Kasten (1980).

1. calculate Angstrom turbidity alpha exponent if not known, from AOD at two wavelengths, `lambda1` and `lambda2`:

        [HIDDEN]

    Example with `lambda1 = 1240nm` and `lambda2 = 550nm`

        [HIDDEN]

2. get `aod` at 700[nm] from `alpha`

        [HIDDEN]

3. From numerically integrated spectral simulations done with Modtran (Berk, 1996), [Molineaux (1998)][2] obtained for the broadband optical depth of a clean and dry atmopshere (fictious atmosphere that comprises only the effects of Rayleigh scattering and absorption by the atmosphere gases other than the water vapor) the following expression where `M` is airmass.

        [HIDDEN]

4. The broadband water vapor optical depth where `pwat` is the precipitable water vapor content of the atmosphere in [cm]. The precision of these fits is better than 1% when compared with Modtran simulations in the range 1 < M < 6 and 0 < w < 5 cm.

        [HIDDEN]

5. Aerosol

    either using ([Molineaux 1998][2])

        [HIDDEN]

    or using (Bird-Hulstrom 1980)

        [HIDDEN]

6. Using the [Kasten pyrheliometric formula (1980)][1], the Linke turbidity at M

            [HIDDEN]

This derivation was developed in collaboration with Armel Oumbe @aoumbe

[1]: http://www.asrc.albany.edu/people/faculty/perez/publications/Solar%20Resource%20Assessment%20and%20Modeling/Papers%20on%20Resource%20Assessment%20and%20Satellites/new%20airmass%20for%20Linke-02.pdf
[2]: http://www.cuepe.ch/html/biblio/pdf/molineaux-ineichen%201998%20%20-%20Equivalence%20of%20pyrheliometric%20and%20aerosol%20optical%20depth%20(ao).pdf

references:
1. [_A new airmass independent formulation for the Linke turbidity coefficient_, Ineichen, Perez](http://www.asrc.albany.edu/people/faculty/perez/publications/Solar%20Resource%20Assessment%20and%20Modeling/Papers%20on%20Resource%20Assessment%20and%20Satellites/new%20airmass%20for%20Linke-02.pdf)
2. [**Equivalence of pyrheliometric and monochromatic aerosol optical depth at a single key wavelength**, Mlineaux, Ineichen and O'Neill](http://www.cuepe.ch/html/biblio/pdf/molineaux-ineichen%201998%20%20-%20Equivalence%20of%20pyrheliometric%20and%20aerosol%20optical%20depth%20(ao).pdf)

### Additional contract requirements

The following public functions are provided in the module `pvlib.atmosphere`:

- `angstrom_alpha(aod1, lambda1, aod2, lambda2)` returns the Angstrom exponent α for aerosol optical depths measured at wavelengths in nm:
  `α = -log(aod1 / aod2) / log(lambda1 / lambda2)`.
- `angstrom_aod_at_lambda(aod0, lambda0, alpha, lambda1=700.0)` returns AOD at target wavelength `lambda1` in nm, from reference AOD `aod0` at `lambda0` in nm: `aod1 = aod0 * (lambda1 / lambda0)**(-alpha)`. The target defaults to 700 nm and may be supplied by the caller.
- For absolute airmass `M`, the clean-and-dry broadband optical-depth contribution is `delta_cda = -0.101 + 0.235 * M**(-0.16)`.
- For precipitable water `pwat` in cm, the water-vapor broadband optical-depth contribution is `delta_w = 0.112 * M**(-0.55) * pwat**0.34`.
- The Molineaux aerosol contribution is the AOD at 700 nm: `delta_a = aod700`. Alternatively, `bird_hulstrom80_aod_bb(aod380, aod500)` estimates broadband aerosol optical depth from AOD at 380 nm and 500 nm as `delta_a = 0.27583 * aod380 + 0.35 * aod500`.
- `kasten96_lt(airmass_absolute, precipitable_water, aod_bb)` returns Linke turbidity using all three contributions above, with `aod_bb` as `delta_a`. At absolute airmass `M`, the Kasten pyrheliometric relationship is `TL = -(9.4 + 0.9*M) * log(exp(-M * (delta_cda + delta_w + delta_a))) / M`.

The airmass and precipitable-water dependencies apply to the supplied values; precipitable water is in centimeters. The aerosol contribution can be provided as AOD at 700 nm or estimated from the two wavelengths using the Bird-Hulstrom relationship.
