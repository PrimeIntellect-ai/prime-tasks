Semicolon being stripped out of export statement
In versions 0.0.8 and 0.0.7 (at least), the following export statement gets its semicolon stripped:

```
export default connect(mapStateToProps)(MyComponent);
```
becomes
```
export default connect(mapStateToProps)(MyComponent)
```

More info and a test case here: https://github.com/jlongster/prettier/pull/101#issuecomment-273381178
