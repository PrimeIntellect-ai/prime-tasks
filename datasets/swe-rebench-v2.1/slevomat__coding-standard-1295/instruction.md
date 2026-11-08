Option to only count logical lines of code in SlevomatCodingStandard.Functions.FunctionLength ?
Was curious if you folks would be open to adding an option to only count logical lines of code in the SlevomatCodingStandard.Functions.FunctionLength` rule?

If so, I'd be up for taking a crack at a pull request. Thanks.

### Additional contract requirements

The FunctionLength rule provides `includeComments` and `includeWhitespace` settings to control whether comment lines and blank or whitespace-only lines, respectively, contribute to the count. Both settings default to false. By default, function length counts logical code lines only: comment-only lines and blank or whitespace-only lines do not contribute to the count.
