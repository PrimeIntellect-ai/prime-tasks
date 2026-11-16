Support flag to require latest version of SUSHI
During the FHIR IG publication workflow, it is very important that the latest version of SUSHI be used. To support this, SUSHI should introduce an optional flag that indicates that SUSHI should exit with an error if it isn't the latest version (or if it can't determine the latest version).  The default value should be false, but FHIR publication engineers can set the flag when doing a publication.

See: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/FSH.20install.20problem/near/281720829
SUSHI should only warn when it cannot determine latest version (unless --require-latest flag is set)
Currently, SUSHI issues an error if it can't reach NPM to determine if it is running the latest version.  This is likely too strong, especially for authors who may be intentionally running a different version of SUSHI.  This should be demoted to be a warning.

If SUSHI is run w/ the `--require-latest` flag, however, SUSHI should _still_ exit w/ an error.

### Additional contract requirements

- When SUSHI cannot determine the latest version, the warning must contain `Unable to determine the latest version of sushi.`
