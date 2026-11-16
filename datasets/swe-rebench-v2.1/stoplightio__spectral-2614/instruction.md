Support more than 2 logicals in XOR core function
**Describe the bug**
In Spectral5.9.2, the core XOR function could accept more than 2 items in its properties' list. In Spectral6+, the core XOR function only appears to support two logical.

**To Reproduce**
Create a ruleset that leverages the core XOR function:

  each-component-property-must-contain-only-one:
    given: $.components.*.*.properties.*
    recommended: true
    severity: warn
    then:
      function: xor
      functionOptions:
        properties:
          - type
          - oneOf
          - $ref

This rule running on 5.9.2 will work with no issue
This rule running on 6+ will result in the following error:
Error #1: "xor" and its "properties" option support 2-item tuples, i.e. ["id", "name"]

**Expected behavior**
The XOR function will behave in the way that it always has, allowing more than just 2 logicals.

**Additional context**
I understand that from an electrical perspective, an XOR gate only takes two inputs, but XOR functionality can support an unlimited number of inputs in practical use. If this was an intended behavior change, then so be it, it just seems like an odd decision to make as it breaks compatibility and the docs page still lists the function as supporting a list of logicals.

Judging by commit histories, it looks like the xor function was completely redesigned in 6.0.0alpha1, this redesign seems to have limited it to two logicals
