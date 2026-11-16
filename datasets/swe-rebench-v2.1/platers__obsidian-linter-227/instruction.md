[BUG] remove-multiple-spaces inconsistent...
I commonly see Linter leave multiple spaces after punctuation, and sometimes before:

<img width="647" alt="image" src="https://user-images.githubusercontent.com/42705243/173258829-4aac4451-e2f2-4e65-af05-f0721d3ce108.png">

possibly relevant configuration items:
remove-multiple-spaces ON
remove-trailing-spaces ON
two space linebreak ON
space between Chinese and English or numbers OFF

### Additional contract requirements

In prose, reduce repeated spaces immediately before or after punctuation to a single space. Remove repeated in-line spaces while preserving two trailing spaces used for a line break.
