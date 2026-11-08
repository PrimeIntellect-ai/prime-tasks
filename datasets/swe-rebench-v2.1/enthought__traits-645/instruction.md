Long type deleted?
Hi,

It seems that Long type has disappeared in las t version from git source.

So, for instance, Mayavi fails to start:


File "/usr/local/lib/python3.7/dist-packages/mayavi-4.7.2.dev0-py3.7-linux-x86_64.egg/tvtk/pyface/picker.py", line 24, in <module>
    from traits.api import HasTraits, Trait, Long, Array, Any, Bool, Float, \
ImportError: cannot import name 'Long' from 'traits.api' (/usr/local/lib/python3.7/dist-packages/traits-6.0.0.dev1284-py3.7-linux-x86_64.egg/traits/api.py)

Am I doing something wrong?

Thanks in advance.

PS : Python 3.7.3, Traits 6.0.0 dev 1284
