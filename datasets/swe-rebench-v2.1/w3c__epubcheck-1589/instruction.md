role="math" on images
When following the WAI ARIA 1.2 example for using `role="math"` on an image element to indicate that it represents a mathematical expression (https://www.w3.org/TR/wai-aria-1.2/#example-8), EPUBCheck reports an ERROR RSC-005 stating that the value of the "role" attribute is invalid.

From the WAI ARIA 1.2 spec:

> While it is not ideal to use an image of a mathematical expression, there exists a significant amount of legacy content where images are used to represent mathematical expressions. Authors SHOULD ensure that images of math are labeled by text that describes the mathematical expression as it might be spoken.

However, EPUBCheck doesn't recognize `math` as a valid value for the `role` attribute, resulting in a false positive error.

Here you can find a sample EPUB file exhibiting this issue for testing purposes: [quadratic-formula.epub.zip](https://github.com/w3c/epubcheck/files/15401438/quadratic-formula.epub.zip)
