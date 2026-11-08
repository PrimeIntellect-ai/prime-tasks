`.write()` convenience function
The use of this module in WSK is currently a bit [verbose](https://github.com/google/web-starter-kit/blob/7ab4b8b39592b825bc2b24f920e27447cce990f9/gulpfile.js#L218-L254). Would be nice to be able to simplify it a bit. First I think this module should have a convenience method to write the file to disk.


From:

```js
var rootDir = 'dist';

swPrecache({
  cacheId: packageJson.name || 'web-starter-kit',
  dynamicUrlToDependencies: {
    './': [path.join(rootDir, 'index.html')]
  },
  staticFileGlobs: [
    rootDir + '/fonts/**/*.woff',
    rootDir + '/images/**/*',
    rootDir + '/scripts/**/*.js',
    rootDir + '/styles/**/*.css',
    rootDir + '/*.{html,json}'
  ],
  stripPrefix: path.join(rootDir, path.sep)
}, function (error, serviceWorkerFileContents) {
  if (error) {
    return callback(error);
  }
  fs.writeFile(path.join(rootDir, 'service-worker.js'),
    serviceWorkerFileContents, function (error) {
    if (error) {
      return callback(error);
    }
    callback();
  });
});
```

To:

```js
var rootDir = 'dist';

swPrecache.write('service-worker.js', {
  rootDir: 'dist',
  cacheId: packageJson.name || 'web-starter-kit',
  dynamicUrlToDependencies: {
    './': [path.join(rootDir, 'index.html')]
  },
  staticFileGlobs: [
    rootDir + '/fonts/**/*.woff',
    rootDir + '/images/**/*',
    rootDir + '/scripts/**/*.js',
    rootDir + '/styles/**/*.css',
    rootDir + '/*.{html,json}'
  ],
  stripPrefix: path.join(rootDir, path.sep)
}, function () {});
```

And since we specify a `rootDir` option, we might be able to get rid of the `stripPrefix` option usage and the `rootDir` thing in `staticFileGlobs`.

### Additional contract requirements

- Provide a convenience method that writes generated service-worker source to the specified file path.
- Preserve the existing ability to obtain generated service-worker source through a callback, independently of writing it to a file.
- Report generation and file-writing errors through the write callback, and invoke the success callback after the file has been written.
