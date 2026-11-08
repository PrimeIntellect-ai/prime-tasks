Invalid conversion from 3-char hex-color to 6-char hex color
### Prerequisites

- [X] I understand and accept the project's [code of conduct](https://github.com/PrestaShop/PrestaShop/blob/develop/CODE_OF_CONDUCT.md).
- [X] I have already [searched in existing issues](https://github.com/PrestaShop/PrestaShop/issues?q=is%3Aissue+label%3ABug) and found no previous report of this bug.

### Describe the bug and add attachments

Here the formula to convert from 3-char hex-color to 6-char hex color is wrong https://github.com/PrestaShop/PrestaShop/blob/dcdd11673033095fd31b65cca6d9ddb0325464c3/src/Core/Util/ColorBrightnessCalculator.php#L62-L64

For instance, the color `#0F1` will be converted to `#0F10F1`, which is wrong. `#00FF11` would be correct

### Expected behavior

I expect the conversion from 3-char hex-color to 6-char hex color to give a correct result.

### Steps to reproduce

For devs, not QA-team 😉
1. Look at this code https://github.com/PrestaShop/PrestaShop/blob/dcdd11673033095fd31b65cca6d9ddb0325464c3/src/Core/Util/ColorBrightnessCalculator.php#L62-L64
2. Imagine what it does and compare to standards

### PrestaShop version(s) where the bug happened

develop

### PHP version(s) where the bug happened

7.4

### If your bug is related to a module, specify its name and its version

_No response_
