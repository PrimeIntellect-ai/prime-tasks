(isMobilePhone): es-CO locale, passing landlines as valid
**Describe the bug**
the regex in [this](https://github.com/validatorjs/validator.js/commit/302d2957c924b515cb22f7e87b5e84fee8636d6e) commit is passing landlines as valid.
isn't the function isMobilePhone() intended to validate Mobile phones Only?

please refer to
Landlines: https://en.wikipedia.org/wiki/Telephone_numbers_in_Colombia#Landline_service
Mobile: https://en.wikipedia.org/wiki/Telephone_numbers_in_Colombia#Mobile_service

**Examples**
0698345 and 9821235 passes as valid, are (apparently) landlines, not mobile

**Additional context**
Validator.js version: 13.5.2 (imported in express-validator 6.10.0)
Node.js version: 14.15.4
OS platform: Arch Linux
