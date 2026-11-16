[nemo] PSyclone loses ‘ELEMENTAL’ and ‘IMPURE ELEMENTAL’ subroutine prefixes
Simon has reported that:

PSyclone appears to falsely drop ‘ELEMENTAL’ and ‘IMPURE ELEMENTAL’ subroutine prefixes. ‘ELEMENTAL’ and ‘IMPURE ELEMENTAL’ prefixes have recently been added to some functions in NEMO ‘main’. In builds without AGRIF processing these functions appear to be reproduced correctly by PSyclone, but after AGRIF processing the prefixes additionally apply to subroutines and seem to disappear during PSyclone processing.

We've discussed having the `ELEMENTAL` property previously. I guess this would need an extension to `RoutineSymbol`.

![image](https://user-images.githubusercontent.com/17409212/234906574-63149d4f-ef4f-4846-a19d-eb5354fc9a2e.png)

### Additional contract requirements

Processed subroutines must retain whether they are elemental, including when declared with an `IMPURE ELEMENTAL` prefix. Expose this status through a queryable `RoutineSymbol.is_elemental` property.
