allow var functions in style.color values
Hi,

I've seen that when I try to insert a value to style.color a function called parseColor not allow to use values with var function like var(--customVar).

[HIDDEN] but maybe there is a more transversal solution wich is being implementig to support this kind of values in all properties.

Thank you for your help

### Additional contract requirements

CSS `var()` values are in scope for regular CSS properties generally, not only `color`. A declaration must accept values containing `var()` (including fallback values, nested variable fallbacks, and variables inside `calc()`) for properties such as colors and measurements. Reading the declaration must retain the variable references and the meaning of the supplied value; insignificant whitespace may be normalized.
