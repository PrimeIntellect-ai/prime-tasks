Interface to unify Pdf, FileBlock, Image
Currently these share the same underlying structure, though I guess it's not guaranteed to stay that way. To reduce switch-case statements in client code, it would be helpful to define an interface to get these common fields, maybe
```
type DownloadableFileBlock interface {
  Block
  GetURL() string
  GetExpiryTime() *time.Time
}
```
