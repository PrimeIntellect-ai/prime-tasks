CLI option to return non-zero exit code when certain license type found in totals
Add a CLI option (`-f` or `--fail`) that defaults to an empty vector, that will hold license type and return non-zero exit code if the license type(s) is(/are) found in license type totals.

E.g. return [exit code 1](https://tldp.org/LDP/abs/html/exitcodes.html) if at least one license of type `Permissive` or `Other` is found:
```
pip-license-checker -r resources/requirements.txt --fail Permissive --fail Other
```
