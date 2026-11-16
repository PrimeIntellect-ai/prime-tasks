Total gradient amplitude transformation
**Description of the desired feature:**
<!--
Add as much detail as you can in your description below. If possible, include an
example of how you would like to use this feature (even better if it's a code
example).
-->

A nice transformation to add to `harmonica` is the _total gradient amplitude_ (aka _analytic signal_), defined in Roest et al (1992) as
$$|A(x, y)| = \sqrt{\left( \frac{\partial M}{\partial x} \right)^2 + \left( \frac{\partial M}{\partial y} \right)^2 + \left( \frac{\partial M}{\partial z} \right)^2}$$

Roest, W. & Verhoef, Joyce & Pilkington, Mark. (1992). Magnetic interpretation using 3-D analytic signal. GEOPHYSICS. 57. 116-125. 10.1190/1.1443174.



**Are you willing to help implement and maintain this feature?**
<!--
Every feature we add is code that we will have to maintain and keep updated.
Please let us know if you're willing to help maintain this feature in the future.
-->
I will try to implement it but no promises about maintenance 😅

### Additional contract requirements

- Expose the transformation as the public callable `harmonica.total_gradient_amplitude(grid)`.
