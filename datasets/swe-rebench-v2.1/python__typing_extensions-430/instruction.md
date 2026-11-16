Add `typing_extensions.TypeExpr`
We should provide TypeExpr from PEP-747 in typing_extensions. @davidfstr are you interested in doing this? The runtime implementation is likely going to be very simple.

Once it's in typing-extensions, I may work on implementing TypeExpr support in pyanalyze since we have some internal use cases.
