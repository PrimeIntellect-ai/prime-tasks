uglifyjs-webpack-plugin cannot uglify any file
this is my code:
```
new UglifyJsPlugin({
    uglifyOptions: {
         ie8: false,
	 ecma: 8,
	 //parse: {...options},
	 mangle: {
		 properties: {
		          // mangle property options
		  }
	  },
	 output: {
		   comments: false,
		   beautify: false
	  },
	 compress: {
	  },
	 warnings: false
    }
 })
```
 I used es7, es6, if i use webpack.optimize.UglifyJsPlugin , it can work normally.

```
"uglifyjs-webpack-plugin": "^1.1.8",
 "webpack": "^3.10.0"
```

### Additional contract requirements

With default options, JavaScript assets whose emitted filenames have query-string suffixes must be selected and minified.
