`readdir` with `withFileTypes:true` incorrectly includes file name in `path`
The test here
https://github.com/streamich/memfs/blob/6f4e72e889b578a62110c2e57f79f78e9dbca408/src/__tests__/volume/readdirSync.test.ts#L108

is wrong - node.js actually doesn't include the file name in the path.

So the expectation should be
`{ mode: 33206, name: 'af1', path: '/z' },`
