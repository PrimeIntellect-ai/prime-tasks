🐛within-line insertion/deletion detection is not working in all cases that work with diff-highlight
Applying [this diff](https://gist.github.com/dasl-/b78f823d62a6b27721dd1dbf3a9c4323) to your project, here is the result from delta:

![delta](https://user-images.githubusercontent.com/1332576/81441085-218bd200-913f-11ea-9a78-c47da5c0e591.png)

And here is the result from diff-highlight:
![diff-highlight](https://user-images.githubusercontent.com/1332576/81441116-2d779400-913f-11ea-8b12-cd13a5386b40.png)

So diff-highlight is doing a better job of detecting the within-line deletion.

### Additional contract requirements

Delta must detect and visibly distinguish deleted text within a changed line, as demonstrated by the supplied reproduction and its diff-highlight comparison.
