undefined name for nested view isn't reported as an error
Here's a quick example.  I have a valid view defined for my_rec_t and then an invalid view which does not report any errors, and actually may contain more than one error.  This is a quick shrinking on an error I had on a real design that was using nested views more properly, but I had a typo in my nested view, meaning that it was undefined, and there were no errors reported. Vivado also handily crashes rather than providing a useful error so finding my typo was fun!

I think the undefined_view should be flagged by the LSP in this case since undefined_view isn't a known identifier at all.


```
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package test is
    type my_rec_t is record
        a : std_logic;
        b : std_logic;
     end record;
     view my_valid_view of my_rec_t is
         a : in;
         b : out;
     end view;
     view invalid_view of my_rec_t is
         a : view undefined_view; -- this should be an error, undefined_view doesn't exist
         b : view undefined_view; -- this should be an error, undefined_view doesn't exist
     end view;

end package;
```

### Additional contract requirements

- An undefined name used as a nested view element must be reported as an error
  with the diagnostic message `No declaration of '<name>'` and error code
  `Unresolved`, located at the undefined name.
- Every occurrence of an undefined nested-view name must be reported: if the same
  undefined name appears more than once, each occurrence is an error.
