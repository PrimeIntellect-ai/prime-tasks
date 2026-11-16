Switch: Label is repeated in an unusual format when using VoiceOver in Safari
### Description

Using VoiceOver to read out the content of the Switch component and toggle it on/off.

The content is not read as expected. The label is repeated in the unusual format: `<my label text>and 2 more item`.

The Switch has been tested in Edge using VoiceOver and it is read out as expected without the repeated text.

### Reproduction

Screen recording shared internally on Slack as StackBlitz is not working for Safari

### Steps to reproduce

_No response_

### JIRA ticket numbers (Sage only)

_No response_

### Suggested solution

_No response_

### Carbon version

138.0.2

### Design tokens version

_No response_

### Relevant browsers

Safari

### Relevant OSs

MacOS

### Additional context

_No response_

### Confidentiality

- [X] I confirm there is no confidential or commercially sensitive information included.

### Additional contract requirements

- When the new validation design is enabled, the Switch input has an accessible name matching its label, without hint or validation text included in the name.
- In that mode, the input’s accessible description includes the hint text followed by any provided error or warning message.
