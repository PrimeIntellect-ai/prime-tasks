Add validation that anonymous/reduced chemical formulae are in fact reduced
Prompted by https://github.com/aiidateam/aiida-optimade/issues/279.

We should add validators that check that the chemical formulae presented in `chemical_formula_reduced` and `chemical_formula_anonymous` are in fact reduced, e.g. that for A<sub>x</sub>B<sub>y</sub>C<sub>z</sub>, `math.gcd([x, y, z]) == 1`.

This is important to truly enable filtering on chemical formulae.
