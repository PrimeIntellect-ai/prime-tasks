[QUESTION] ConformanceLevel for PROFILE_XRECHNUNG_3 should be set to XRECHNUNG?
### Before Submitting an Issue
To help us assist you efficiently, we require confirmation of the following:
- [x] I have read the [documentation](https://github.com/horstoeko/zugferd/wiki) and could not find a solution to my issue.
- [x] I have searched open and closed [issues](https://github.com/horstoeko/zugferd/issues) to ensure my issue has not already been reported.

**Describe the bug**
PDF/A-3 Documents with `ZugferdProfiles::PROFILE_XRECHNUNG_3` reports a ConformanceLevel of `'EN 16931'`. Should this not be `'XRECHNUNG'` due to conformance with EN 16931 AND German federal standards?

**To Reproduce**
Steps to reproduce the behavior:
```php
$document = ZugferdDocumentBuilder::createNew(ZugferdProfiles::PROFILE_XRECHNUNG_3);
$pdfCreator = new ZugferdDocumentPdfBuilder($documentBuilder, $pdf);
$document = $pdfCreator->generateDocument();
```

**Expected behavior**
A clear and concise description of what you expected to happen.
`<ConformanceLevel>XRECHNUNG</ConformanceLevel>`

What happens?
`<ConformanceLevel>EN 16931</ConformanceLevel>`
