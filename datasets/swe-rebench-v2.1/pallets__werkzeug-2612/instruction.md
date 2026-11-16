Increase default work factor for PBKDF2 to 600,000 iterations
https://github.com/pallets/werkzeug/blob/bba2109e276ab876b8d64e2b967412cb6da1d865/src/werkzeug/security.py#L12

The value has not been updated for a few years. I propose increasing it to the same number as the next release of Django will use.

See https://github.com/django/django/pull/16521 and https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html#pbkdf2.
