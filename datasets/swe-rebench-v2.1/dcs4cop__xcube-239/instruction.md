xcube server to return default color bar
**Is your feature request related to a problem? Please describe.**

xcube server will return any color bar associated with a variable, independent whether the color bar name is known or not, e.g. `"Plasma"` instead of `"plasma"`. xcube viewer will show a missing color bar image in this case:

![image](https://user-images.githubusercontent.com/206773/69242538-56ac6400-0ba1-11ea-9a11-2c3635218bff.png)

**Describe the solution you'd like**

Let xcube server report the actual default color bar used in the case, i.e. "viridis".

**Describe alternatives you've considered**
