[Enhancement] Components property Array of other components
**Is your feature request related to a problem? Please describe.**
We fixed the problem with multiple primitive types on one property in this commit https://github.com/BRIKEV/express-jsdoc-swagger/commit/b2bd217b341102d40f2fa89e6d2d68f54e680a84 but we need to do the same for Components references. It should be similar like we do in [schemas](https://github.com/BRIKEV/express-jsdoc-swagger/blob/master/transforms/paths/schema.js)

**Describe the solution you'd like**
We need to display and Album schema with an Array of Songs schemas.
