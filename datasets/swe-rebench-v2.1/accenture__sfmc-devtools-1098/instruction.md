[BUG] In the doc .md files for Data Extensions, Decimal field type has only presicion, not scale
### Is there an existing issue for this?

- [X] I have searched the existing issues

### Current Behavior

.json files retrieved for Data Extensions, for Decimal fields, contain both Scale and Max Length (Precision). But doc .md files take only value from Max Length field. So if the Decimal field has length 18 and scale 8, in doc .md file, only Max Length of 18 is included and scale 8 is ignored.

### Expected Behavior

If Decimal field have precision 18 and scale 8, I prefer to see it in doc .md file in the same way as in SFMC UI - as 18,8. It would be valuable, when sharing the schama of the tables with teams outside SFMC.

### Steps To Reproduce

1. Retrieve Data Extensions.
2. Open .md file for one of the Data Extensions with Decimal fields.
3. Previed .md file.
4. See that only precision is shown in Max Lenght field, and scal is ignored.


### Version

5.2.0

### Environment

- OS: Windows 11
- Node: 18.15.0
- npm: 9.8.1


### Participation

- [X] I am willing to submit a pull request for this issue.

### Additional comments

_No response_
