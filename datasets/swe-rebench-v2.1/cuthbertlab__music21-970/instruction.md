Decide whether to support class strings as keys for `Stream.__getitem__`
https://github.com/cuthbertLab/music21/blob/ebc47a1fbc9d65981bc52928593b4b564ae96cd5/music21/stream/base.py#L322-L324

Doesn't work as described; only names work, not strings:

```
>>> h = corpus.parse('handel')
>>> h[stream.Part]
<music21.stream.Score 0x110207ee0>
>>> h['stream.Part']
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/Users/jwalls/music21/music21/stream/base.py", line 451, in __getitem__
    raise KeyError(f'provided key ({k}) does not match any id or group')
KeyError: 'provided key (stream.Part) does not match any id or group'
>>> h['Part']
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/Users/jwalls/music21/music21/stream/base.py", line 451, in __getitem__
    raise KeyError(f'provided key ({k}) does not match any id or group')
KeyError: 'provided key (Part) does not match any id or group'
```

**More information**
Shall we correct the docs or add the feature?

Here's adding the feature:
```diff
diff --git a/music21/stream/base.py b/music21/stream/base.py
index 4d8f92316..3e792a754 100644
--- a/music21/stream/base.py
+++ b/music21/stream/base.py
@@ -398,7 +398,8 @@ class Stream(core.StreamCoreMixin, base.Music21Object):
         KeyError: "provided class (<class 'music21.layout.StaffLayout'>) does
             not match any contained Objects"

-        Changed in v7. -- out of range indexes now raise an IndexError, not StreamException
+        Changed in v7. -- out of range indexes now raise an IndexError, not StreamException.
+        Unsupported types now raise TypeError. Strings now supported for class names.
         '''
         # need to sort if not sorted, as this call may rely on index positions
         if not self.isSorted and self.autoSort:
@@ -447,15 +448,20 @@ class Stream(core.StreamCoreMixin, base.Music21Object):
                 groupStream = self.iter.getElementsByGroup(k)
                 if groupStream:
                     return groupStream.stream()
-                else:
-                    raise KeyError(f'provided key ({k}) does not match any id or group')
-        elif isinstance(k, type(type)):
+                # else:
+                    # raise KeyError(f'provided key ({k}) does not match any id or group')
+
[HIDDEN]
             [HIDDEN]
-            else:
+            elif isinstance(k, type):
                 raise KeyError(f'provided class ({k}) does not match any contained Objects')
+            else:
+                raise KeyError(f'provided key ({k}) does not match any id, group, or class name')
+
+        raise TypeError(f'Get items by int, slice, id, or class; got {type(k)}')
```

### Additional contract requirements

- A string key that names a class (for example `'Note'` or `'Part'`) is treated as a
  class-name lookup and returns the matching elements as an iterable of those elements.
- Existing string keys keep working: a string beginning with `#` returns the element with that id, and a
  string beginning with `.` returns an iterable of the elements in that group.
