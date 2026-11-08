React version "detect" is slow, particularly for no-unknown-property
I've been timing and profiling ESLint runs at Airbnb and noticed that react/no-unknown-property is particularly slow for us when using the "detect" setting for React version.

When running ESLint using `TIMING=1` on a directory that contains about 500 files to be linted in it, react/no-unknown-property shows up as taking about 1700ms.

Looking at the callstacks in the profiler, it seems that when this rule calls getStandardName for every JSXAttribute here, it will actually do all of the work to detect the React version every time to determine the correct set of DOM property names.

https://github.com/yannickcr/eslint-plugin-react/blob/ef9a51225e3d5f6cb7cbdc3ec0382ad49246034b/lib/rules/no-unknown-property.js#L275

![image](https://user-images.githubusercontent.com/195534/84674049-17a08000-aef0-11ea-985c-49e01bab3be8.png)

By specifying the react version in our ESLint config, the no-unkown-property rule drops out of the top 10 slowest rules entirely, with the 10th slowest clocking in at 180ms.

I think it would be a good idea to [HIDDEN]: https://github.com/yannickcr/eslint-plugin-react/blob/ef9a51225e3d5f6cb7cbdc3ec0382ad49246034b/lib/util/version.js#L17-L33

Would you be open to a PR that did this?

### Additional contract requirements

- When the React version setting is `"detect"`, reuse the previously detected React version on subsequent detection calls rather than repeating detection.
- Export a function `resetDetectedVersion()` from `lib/util/version.js` (available as `versionUtil.resetDetectedVersion`). It takes no arguments and returns no value, and it discards any React version previously detected for the `"detect"` setting so that the next detection starts fresh.
