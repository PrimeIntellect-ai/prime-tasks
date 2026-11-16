Typo in klucher irradiance model
This change looks like a typo:
https://github.com/pvlib/pvlib-python/commit/1f968a034f74e46f021f3a6b85ea86c5e1ad6cf8#diff-9e2b3ebf5d45c478fee41a88b0e5f44eR671

### Additional contract requirements

- For the Klucher irradiance model, calculate sky diffuse irradiance as \(DHI \cdot \frac{1+\cos(\beta)}{2} \cdot [1+F\sin^3(\beta/2)] \cdot [1+F\cos^2(AOI)\sin^3(\theta_z)]\), where \(F=1-(DHI/GHI)^2\), \(\beta\) is surface tilt, \(AOI\) is the angle of incidence, and \(\theta_z\) is solar zenith. Angles are in degrees when supplied as model inputs.
