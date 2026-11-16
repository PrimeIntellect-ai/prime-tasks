ImageCropper: originalFilename does not match the name attribute of DefaultStreamedContent
### Describe the bug

`CroppedImage `object has an `originalFilename` attribute which is the name of the image that has been cropped.

If one is cropping an image which is obtained via a `StreamContent` rather than a static file, then there is no filename as such. Conveniently, a name can still be set to the `StreamContent`:

`StreamedContent imageAsStream = DefaultStreamedContent.builder()**.name("example")**.contentType("image/png").stream(() -> stream).build();`

yet, when one calls the method `getOriginalFileName `on the `CroppedImage`, it produces a `String `which is the result of the `toString()` method of the original `StreamContent`, instead of returning the `name` attribute that had been set in the builder.

Use case: I need to match the original pic with the cropped pic, and it would make my life easier if I could just use their names to match them.




### Reproducer

This case is deeply embedded in an app, can't create a reproducer.

### Expected behavior

The `originalFilename `attribute of `CroppedImage `should match the `name `attribute of the image that was cropped and which originated from a `DefaultStreamContent`.

### PrimeFaces edition

Community

### PrimeFaces version

12.0

### Theme

default theme

### JSF implementation

Mojarra

### JSF version

2.3

### Java version

17

### Browser(s)

_No response_
