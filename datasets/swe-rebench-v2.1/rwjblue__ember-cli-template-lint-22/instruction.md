Add general file level comment to disable in template.
Should allow ignoring a specific rule or all rules (ala `// jscs disable`)...

### Additional contract requirements

- Use HTML comment directives `<!-- template-lint block-indentation=false -->` or `<!-- template-lint triple-curlies=false -->` to disable the corresponding rule, and `<!-- template-lint disable=true -->` to disable all rules.
