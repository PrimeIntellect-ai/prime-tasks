setattr_original_value flag is ignored when setting overriding a default value in subclass
Almost the same as https://github.com/enthought/traits/issues/1087.

This time validation without checking the flag is done in:
https://github.com/enthought/traits/blob/be82bc039013e8d9beda29b4255458517f74bcc1/traits/trait_type.py#L297-L305

which is executed in a situation like this:
``` python
def test_default_static_override_static(self):
    class BaseFoo(HasTraits):
        bar = Expression()

    class Foo(BaseFoo):
        bar = "3"

    f = Foo()
    self.assertEqual(f.bar, "3")  # fails
    self.assertEqual(f.bar_, compile("3", "<string>", "eval"))
```
