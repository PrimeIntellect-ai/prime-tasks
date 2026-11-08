Include Sommerfeld number in the fluid flow class
According to Friswell et al. in Dynamics of Rotating Machines (2010, page 178), if the magnitude of the load is known, then the bearing eccentricity may be obtained by solving a quartic equation including the Sommerfeld number. The program must be able to calculate the Sommerfeld number and give the eccentricity of the bearing.

### Additional contract requirements

A `PressureMatrix` bearing must provide a `sommerfeld_number(load)` operation that returns the Sommerfeld number for the supplied rotor load. For a supplied load, `PressureMatrix.calculate_eccentricity_ratio(load)` must return the bearing eccentricity divided by radial clearance, obtained from the quartic relationship involving the Sommerfeld number for that load.
