Default to deep copy
Here's a fucking crazy idea - default comparisons to deep. Why are we all typing `.deep` over and over again when almost no one needs shallow, reference comparison. I would even go as far as come up with a new method for `.to.be.reference()` to make your intention clear.

I'm so fucking sick of having to fix my tests because of a missing `.deep` modifier.
