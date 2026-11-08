Remove unnecessary "use strict"
If the parent has a "use strict" directive, it's not necessary to have it in the children.

### Additional contract requirements

A child function's "use strict" directive must be retained when its enclosing scope does not already make the child strict.
