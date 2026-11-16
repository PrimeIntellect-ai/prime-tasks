`unexport` is not backwards-compatible
Was playing with the new `unexport` syntax for `vim-just` and found some weird-looking backwards-incompatible behavior:
```
# In previous versions of just,
# these would create a recipe called "unexport" with parameters "QT_QPA_PLATFORMTHEME" and foo.
# In current just, they unexport QT_QPA_PLATFORMTHEME and create a recipe "foo"
unexport QT_QPA_PLATFORMTHEME \
foo:
	echo Not Foo
unexport QT_QPA_PLATFORMTHEME foo:
	echo Also Not Foo

# just 1.29.0 accepts this line as if it were the two lines
# unexport QT_QPA_PLATFORMTHEME
# and
# foo := 'bar'
# but shouldn't this actually be an error, as it is in previous just versions?
unexport QT_QPA_PLATFORMTHEME foo := 'bar'

# previous versions of just allowed "unexport" to be a recipe name or variable name
# these are now an error, even though they don't conflict with the documented unexport syntax
unexport := 'foo'

unexport:
	echo Unexport Recipe

unexport blah:
	echo {{quote(blah)}}
```
