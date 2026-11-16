'clear' tests are not really testing anything
### Describe the bug

The following test code in `AxiosHeaders.js`

```
  describe('clear', ()=> {
    it('should clear all headers', () => {
      const headers = new AxiosHeaders({x: 1, y:2});

      headers.clear();

      assert.notDeepStrictEqual(headers, {});
    });

    it('should clear matching headers if a matcher was specified', () => {
      const headers = new AxiosHeaders({foo: 1, 'x-foo': 2, bar: 3});

      assert.notDeepStrictEqual(headers, {foo: 1, 'x-foo': 2, bar: 3});

      headers.clear(/^x-/);

      assert.notDeepStrictEqual(headers, {foo: 1, bar: 3});
    });
  });
```

Doesn't fail if you remove the implementation for `headers.clear()`

### To Reproduce

Remove the following lines

```
  clear(matcher) {
    const keys = Object.keys(this);
    let i = keys.length;
    let deleted = false;

    while (i--) {
      const key = keys[i];
      if(!matcher || matchHeaderValue(this, this[key], key, matcher)) {
        delete this[key];
        deleted = true;
      }
    }

    return deleted;
  }
```

to

```
  clear(matcher) {
    return true;
  }
```

### Code snippet

_No response_

### Expected behavior

Tests should fail

### Axios Version

_No response_

### Adapter Version

_No response_

### Browser

_No response_

### Browser Version

_No response_

### Node.js Version

_No response_

### OS

_No response_

### Additional Library Versions

_No response_

### Additional context/Screenshots

_No response_

### Additional contract requirements

- `AxiosHeaders.prototype.clear(matcher)` deletes every header whose name matches `matcher` and keeps the headers whose names do not match. When `matcher` is a string or a regular expression it is tested against the header name, not the header value.
- `AxiosHeaders.prototype.clear()` called without a matcher deletes all headers.
- `AxiosHeaders.prototype.toJSON()` returns a plain object whose values are the normalized string header values; for example `new AxiosHeaders({foo: 1, 'x-foo': 2, bar: 3}).toJSON()` is `{foo: '1', 'x-foo': '2', bar: '3'}`.
