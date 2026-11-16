Passing None on the command line
cc @SylvainCorlay

Hi all,

congrats with the 5.0 release! But with all big releases come bugs :)

In voila we used to pass to a Unicode config a None value by using
```
$ voila --template=None
```
With traitlets 5, this becomes the string 'None'. Any falsy would work for us, but it also does not seem possible to pass an empty string.

Any ideas for workaround, or would this require a fix?

cheers,

Maarten


Related voila PR: https://github.com/voila-dashboards/voila/pull/691
