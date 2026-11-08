Bundled Oclif CLI with PKG is failing to initialize Package.json and Plugins
https://github.com/oclif/core/blob/a9c92867e7cafbff7f6e2339fe0aacb5c648203c/src/util/fs.ts#L13C11-L13C17

It seems it is not working as expected with a cli bundled with **PKG**.
When going through the Root Plugin initialization, and trying to read Package.json, the fs:promise `access` function throws with
```bash
[Error: ENOENT: no such file or directory, access '/snapshot/mycli/package.json'] {
  errno: -2,
  code: 'ENOENT',
  syscall: 'access',
  path: '/snapshot/mycli/package.json'
}
```
I have debugged the content hosted by `pkg`:
```txt
------------------------------- virtual file system
/snapshot
  mycli                                63381336
    run.js                                     533
    package.json                              2356
    oclif.manifest.json                       1965
    dist                                     13275
      index.js                                 238
      commands                                7641
        hello                                  7403
          index.js                            1300
      utils                                   8421
        some                                    780
          index.js                             780
```
[HIDDEN]
Probably a permission error in the virtualized system?

### Additional contract requirements

The CLI must initialize its root package and discover and load its plugins when package files are available through PKG’s virtual filesystem, even if `fs.promises.access` fails for those files.
