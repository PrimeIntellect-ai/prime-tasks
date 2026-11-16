fs.futimes causes gulp build failure on AIX 6
node -v
8.11.4

gulp
@4.0.0

See [https://github.com/nodejs/node/issues/12609](https://github.com/nodejs/node/issues/12609). This causes the following error with gulp on any gulp.dest():

Error: ENOSYS: function not implemented, futime

Currently I'm using a [HIDDEN], but I'm not exactly sure if it's a proper enough solution.

### Additional contract requirements

An `ENOSYS` error from `fs.futimes` must not cause a file write through `gulp.dest()` to fail.
