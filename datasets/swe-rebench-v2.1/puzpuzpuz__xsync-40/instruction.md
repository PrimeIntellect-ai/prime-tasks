Map: make size() public
Hello,

It would be really nice to have this function in the public API:
https://github.com/puzpuzpuz/xsync/blob/d5f0f9d5b79c39bf68bf9771f52f477262972f6f/mapof.go#L325

Thanks!

### Additional contract requirements

- Expose `MapOf[V].Size() int` as a public method that returns the current number of entries in the map (zero when empty).
