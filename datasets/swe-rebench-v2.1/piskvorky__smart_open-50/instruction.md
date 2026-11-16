Get rid of file mode restrictions
Currently `smart_open` is limiting file modes to `('r', 'rb', 'w', 'wb')` [here](https://github.com/piskvorky/smart_open/blob/master/smart_open/smart_open_lib.py#L110).

I don't think there is any reason for this -- remove the restriction and allow whatever mode is supported by the underlying storage ([such as `wb+`](http://stackoverflow.com/questions/34396300/gensim-installation-on-yosemite-using-anaconda)).
