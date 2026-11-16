Get Differential Variables Function
I'm working on some functions that require replacing all differential terms with variables using diff2term. I need to substitute the terms back in later once some intermediate operations are done. It's very difficult to retrieve all of the differential terms in an expression. Right now my plan is to make a function that finds every `"Differential"` string in the string of a given expression. It would be great if there was a function to do this.

### Additional contract requirements

Expose the differential-term retrieval function as `get_differential_vars`. It must find differential terms in symbolic expressions, including terms nested within other expressions or differentials.
