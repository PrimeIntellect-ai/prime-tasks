Not copy new file in watch mode
I use
```
new CopyWebpackPlugin([
    'res/**/*.*'
])
```
and
```
webpack -w --mode=development
```

When watching, if I create a new file (like `res/test.txt`), it would not copy to the output path.
I must restart webpack.
