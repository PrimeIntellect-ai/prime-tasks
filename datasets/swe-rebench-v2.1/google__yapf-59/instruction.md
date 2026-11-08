Breaks code using line continuation with backslashes
This:

    text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Donec a diam lectus. "\
           "Sed sit amet ipsum mauris. Maecenas congue ligula ac quam viverra nec consectetur "\
           "ante hendrerit. Donec et mollis dolor. Praesent et diam eget libero egestas mattis "\
           "sit amet vitae augue. Nam tincidunt congue enim, ut porta lorem lacinia consectetur. "\
           "Donec ut libero sed arcu vehicula ultricies a non tortor. Lorem ipsum dolor sit amet, "\
           "consectetur adipiscing elit. Aenean ut gravida lorem. Ut turpis felis, pulvinar ..."

gets convert to this:

    text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Donec a diam lectus. "
    "Sed sit amet ipsum mauris. Maecenas congue ligula ac quam viverra nec consectetur "
    "ante hendrerit. Donec et mollis dolor. Praesent et diam eget libero egestas mattis "
    "sit amet vitae augue. Nam tincidunt congue enim, ut porta lorem lacinia consectetur. "
    "Donec ut libero sed arcu vehicula ultricies a non tortor. Lorem ipsum dolor sit amet, "
    "consectetur adipiscing elit. Aenean ut gravida lorem. Ut turpis felis, pulvinar ..."

That is, the backslashes causing the string literals to be considered one statement are removed, effectively cutting off the string after the first line.

### Additional contract requirements

Reformatting code that uses backslash-newline line continuations must preserve those continuation markers rather than removing them.

Add a public function `SpliceContinuations(tree)` in module `yapf.yapflib.continuation_splicer`. It accepts a parse tree, inserts a dedicated CONTINUATION node for each backslash-newline continuation marker found in the source, preserving the line number on which the backslash appears, and returns None. The CONTINUATION node type is the public constant `yapf.yapflib.format_token.CONTINUATION`.
