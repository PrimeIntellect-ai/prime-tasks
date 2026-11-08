samefile() is not implemented
Is there a plan for implementing `UPath.samefile()`? I can see how such a method might be difficult to define universally, and that it isn't the same thing as `UPath.__eq__()`, which is implemented, but this broke some code of mine that was usually using `Path.samefile()` and then failed when I passed it a `UPath` instead of a `Path`.

If this is a TODO, then is there anything I can do to help?
