[BUG] Mcdev strips content before and after script tag upon retrieval
### Is there an existing issue for this?

- [X] I have searched the existing issues

### Current Behavior

I recently tried pulling a code snippet, metadata would be asset. This code snippet contains html, ampscript and ssjs script. as of now, when retrieving such code snippets, all the content except the content within the ssjs tags would be lost

### Expected Behavior

_No response_

### Steps To Reproduce

1. Have a content block/code snippet with such content - including html, ampscript, ssjs within.
2. mcdev retrieve this asset using customer key
3. Done. When inspecting the file that has been retrieved, you'd find that the content before the `<script runat="server"> `tag is missing and the same with content after the `</script> `tag.

### Version

6.0.0

### Environment

MacOS, but this doesn't matter. Node and mcdev are of the latest versions.

### Participation

- [X] I am willing to submit a pull request for this issue.

### Additional comments

_No response_

### Additional contract requirements

- The retrieved HTML must format the AMPscript section exactly as `%%[
    /* my ampscript */
]%%`.
