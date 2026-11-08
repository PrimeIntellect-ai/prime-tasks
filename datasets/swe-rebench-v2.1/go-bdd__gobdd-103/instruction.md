Do not require returning the context from a step
**Is your feature request related to a problem? Please describe.**
Returning the context seems unnecessary (since it's internal state is mutated) and it clutters the code.

**Describe the solution you'd like**
Accept the context in the step function parameter list, but don't require returning it.

**Describe alternatives you've considered**
This would make sense if the context was immutable, but it's not.

**Additional context**
Based on our conversation on slack with @bkielbasa I felt like there is a misunderstanding:

> the context is the holder of the state. It has to be kept somewhere so to avoid global variables I decided to do this way. Do you have any better idea?

Accepting the context as a parameter is OK, having to return it as well seems unnecessary.
