Boyer Moore Algorithm
Implement a string matching algorithm - Boyer Moore

Example of the problem
Input:
      txt[] = "THIS IS A TEST TEXT"
      pat[] = "TEST"
Output:
     Pattern found at index 10


Reference #400

### Additional contract requirements

Expose Boyer–Moore matching through the existing public `pydatastructs.strings.find(text, query, algorithm)` function using `algorithm="boyer_moore"`. The search must not examine every character of the text when it can rule out positions: if the query's characters do not occur in a stretch of text, the search should skip past that stretch in one step of the query's length rather than advancing one character at a time. Return the starting index of every occurrence of the query in the text; return no positions when there is no occurrence. For the example above, the returned positions must include index 10.
