Allow whitespace in templates
# Summary

Currently Argo does not allow white space in templating, rendering of `{{workflow.parameters.variable}}` does correctly work, however `{{ workflow.parameters.variable }}` doesn't render the variable. Also `argo lint` did not issue any warning or error.

# Use Cases

I often find it more readable when you can add whitespace to separate markers like `{{` and `}}` from variable names.

---
<!-- Issue Author: Don't delete this message to encourage other users to support your issue! -->
**Message from the maintainers**:

Impacted by this bug? Give it a 👍. We prioritise the issues with the most 👍.
