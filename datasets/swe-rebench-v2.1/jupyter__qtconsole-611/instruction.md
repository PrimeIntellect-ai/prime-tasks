Unable to output boldface and some colors from executing python script in qtconsole.
How would I go about setting a boldfaced text output? The ansi escape sequence does not work:
print('\033[1m This should be boldface.')
You also cannot use HTML or Markdown as neither of these work in qtconsole.

How would I go about outputting a foreground color of yellow?

print('\033[31m This is red.')
print('\033[32m This is green.')
print('\033[33m This is red but is supposed to be yellow.')

I noticed there is some history regarding ansi escape sequences and making text readable when using light or dark background terminal colors.

Is there a way to set boldface and yellow?
