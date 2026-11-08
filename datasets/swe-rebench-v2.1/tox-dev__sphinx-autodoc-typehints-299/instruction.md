Does not handle class attributes
I have a fix for this but it isn't great. More monkey patching. I'll open a PR and provide an explanation there.

Suppose I have the following:

```py
class T:
    """A class"""

    code : CodeType | None
    """An attribute"""
```
#### What I see:

The type for the attribute was rendered directly by `sphinx-autodoc` inconsistently with the way that `sphinx-autodoc-typehints` would render it:

![Screenshot from 2023-01-17 10-16-18](https://user-images.githubusercontent.com/8739626/212979356-a1f5b2e6-de8f-4c10-a371-3d748585c2c7.png)

#### What I'd like to see:

The attribute type rendered by `sphinx-autodoc-typehints`

![Screenshot from 2023-01-17 10-16-59](https://user-images.githubusercontent.com/8739626/212979426-49105630-954b-4ef3-9c56-b2c162b7fc78.png)
