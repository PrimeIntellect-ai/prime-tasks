`Url::from_file_path()` incorrect handling of backslash on linux
Also affects `Url::from_directory_path()`.

Backslashes in paths get left as-is. They should be percent-encoded to `%5C`. Currently that backslash would change to a forward-slash if the output were to be stringified and re-parsed with `Url::parse()`. See the following roundtrip:
```rust
fn main() {
  let path = std::path::PathBuf::from("/a/b/c\\d");
  let url = url::Url::from_file_path(&path).unwrap();
  println!("{}", url.as_str()); // file:///a/b/c\d
  let url2 = url::Url::parse(url.as_str()).unwrap();
  println!("{}", url2.as_str()); // file:///a/b/c/d
  let path2 = url2.to_file_path().unwrap();
  println!("{}", path2.display()); // /a/b/c/d
  //                         Expected /a/b/c\d
}
```
Expected:
```rust
fn main() {
  let path = std::path::PathBuf::from("/a/b/c\\d");
  let url = url::Url::from_file_path(&path).unwrap();
  println!("{}", url.as_str()); // file:///a/b/c%5Cd
  let url2 = url::Url::parse(url.as_str()).unwrap();
  println!("{}", url2.as_str()); // file:///a/b/c%5Cd
  let path2 = url2.to_file_path().unwrap();
  println!("{}", path2.display()); // /a/b/c\d
}
```

On Windows they get swapped to forward-slashes, which is correct for Windows.

### Additional contract requirements

- `Url::from_directory_path()` builds on `Url::from_file_path()` and ensures the
  resulting URL path has a trailing `/`. Backslashes in the directory path are
  percent-encoded as `%5C` just like for `Url::from_file_path()`. For example,
  `Url::from_directory_path(Path::new("/foo/ba\\r"))` yields a URL whose path is
  `/foo/ba%5Cr/`.
