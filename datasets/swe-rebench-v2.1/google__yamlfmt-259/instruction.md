yamlfmt removes comment from yaml with only a comment
```
% cat comment.yml
# comment

% go tool yamlfmt -v comment.yml
The following files were modified:
comment.yml

% cat comment.yml
%
```

Version: 0.17.0
This happens with empty config.

### Additional contract requirements

- When formatting the input `# hi`, the output must be exactly `# hi`, with no trailing newline.
