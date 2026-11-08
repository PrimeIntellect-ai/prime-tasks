useDynamicList 中使用resetList时，数据没有更新
在使用resetList时，对应的表单域中的数据没有变，源码中好像在reset的时候，重置了key，[HIDDEN]，不然表单域中的key没有变，数据不会更新

### Additional contract requirements

- After `resetList` replaces the list, keys returned for replacement items must continue the sequence established by prior items rather than reuse earlier keys, so dependent form fields update.
