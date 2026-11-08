Better default for depth in equivalent sources
**Description of the desired feature:**
<!--
Add as much detail as you can in your description below. If possible, include an
example of how you would like to use this feature (even better if it's a code
example).
-->

From chats with @indiauppal and @birocoles, I learned that Dampney (1969; the original equivalent source paper) advises using depths between 2.5 and 6 times the source spacing (assuming sources in a regular grid). For sources beneath data, like  we use here, a sensible default is 4.5 times the median distance between sources. Me and @indiauppal tested this default and it works well most of the time. Tweaking is always good but this would provide a more sensible default than the fixed value we currently use.

This would break backwards compatibility. I'm not too worried since our docs say that you should always set the `depth` by hand. So changing the default will likely make the interpolation better for the few people who were using the classes without following our advice. But I can do the warning dance if others think it's necessary (but it will take longer to implement).

**Are you willing to help implement and maintain this feature?**
<!--
Every feature we add is code that we will have to maintain and keep updated.
Please let us know if you're willing to help maintain this feature in the future.
-->
Yes. But very happy to let someone else do it (😉 @indiauppal)

### Additional contract requirements

When `depth` is omitted, EquivalentSources must position the fitted sources using a depth of 4.5 times the median distance to a first-neighboring source. This requirement concerns the source coordinates actually used in fitting, not only any reported depth value.
