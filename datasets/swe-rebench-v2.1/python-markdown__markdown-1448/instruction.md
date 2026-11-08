"Unterminated character set" exception when using extra extension
Hi,

When using the "extra" extensions, some invalid markdowns (i think?) are causing exceptions rather than returning plaintext line.

Example:

```
txt = """
*[^1^]: This is going to crash if extra extension is enabled
"""

import markdown
ok = markdown.markdown(txt, extensions=[])
not_ok = markdown.markdown(txt, extensions=['extra'])
```

Is this expected behavior?

Full exception stack trace:
```
Cell In[29], line 7
      5 import markdown
      6 ok = markdown.markdown(txt, extensions=[])
----> 7 not_ok = markdown.markdown(txt, extensions=['extra'])

File lib/python3.10/site-packages/markdown/core.py:482, in markdown(text, **kwargs)
    464 """
    465 Convert a markdown string to HTML and return HTML as a Unicode string.
    466
   (...)
    479
    480 """
    481 md = Markdown(**kwargs)
--> 482 return md.convert(text)

File lib/python3.10/site-packages/markdown/core.py:357, in Markdown.convert(self, source)
    354     self.lines = prep.run(self.lines)
    356 # Parse the high-level elements.
--> 357 root = self.parser.parseDocument(self.lines).getroot()
    359 # Run the tree-processors
    360 for treeprocessor in self.treeprocessors:

File lib/python3.10/site-packages/markdown/blockparser.py:117, in BlockParser.parseDocument(self, lines)
    115 # Create an `ElementTree` from the lines
    116 self.root = etree.Element(self.md.doc_tag)
--> 117 self.parseChunk(self.root, '\n'.join(lines))
    118 return etree.ElementTree(self.root)

File lib/python3.10/site-packages/markdown/blockparser.py:136, in BlockParser.parseChunk(self, parent, text)
    120 def parseChunk(self, parent: etree.Element, text: str) -> None:
    121     """ Parse a chunk of Markdown text and attach to given `etree` node.
    122
    123     While the `text` argument is generally assumed to contain multiple
   (...)
    134
    135     """
--> 136     self.parseBlocks(parent, text.split('\n\n'))

File lib/python3.10/site-packages/markdown/blockparser.py:158, in BlockParser.parseBlocks(self, parent, blocks)
    156 for processor in self.blockprocessors:
    157     if processor.test(parent, blocks[0]):
--> 158         if processor.run(parent, blocks) is not False:
    159             # run returns True or None
    160             break

File lib/python3.10/site-packages/markdown/extensions/abbr.py:61, in AbbrPreprocessor.run(self, parent, blocks)
     58 abbr = m.group('abbr').strip()
     59 title = m.group('title').strip()
     60 self.parser.md.inlinePatterns.register(
---> 61     AbbrInlineProcessor(self._generate_pattern(abbr), title), 'abbr-%s' % abbr, 2
     62 )
     63 if block[m.end():].strip():
     64     # Add any content after match back to blocks as separate block
     65     blocks.insert(0, block[m.end():].lstrip('\n'))

File lib/python3.10/site-packages/markdown/extensions/abbr.py:94, in AbbrInlineProcessor.__init__(self, pattern, title)
     93 def __init__(self, pattern: str, title: str):
---> 94     super().__init__(pattern)
     95     self.title = title

File lib/python3.10/site-packages/markdown/inlinepatterns.py:297, in InlineProcessor.__init__(self, pattern, md)
    287 """
    288 Create an instant of an inline processor.
    289
   (...)
    294
    295 """
    296 self.pattern = pattern
--> 297 self.compiled_re = re.compile(pattern, re.DOTALL | re.UNICODE)
    299 # API for Markdown to pass `safe_mode` into instance
    300 self.safe_mode = False

File lib/python3.10/re.py:251, in compile(pattern, flags)
    249 def compile(pattern, flags=0):
    250     "Compile a regular expression pattern, returning a Pattern object."
--> 251     return _compile(pattern, flags)

File lib/python3.10/re.py:303, in _compile(pattern, flags)
    301 if not sre_compile.isstring(pattern):
    302     raise TypeError("first argument must be string or compiled pattern")
--> 303 p = sre_compile.compile(pattern, flags)
    304 if not (flags & DEBUG):
    305     if len(_cache) >= _MAXCACHE:
    306         # Drop the oldest item

File lib/python3.10/sre_compile.py:788, in compile(p, flags)
    786 if isstring(p):
    787     pattern = p
--> 788     p = sre_parse.parse(p, flags)
    789 else:
    790     pattern = None

File lib/python3.10/sre_parse.py:955, in parse(str, flags, state)
    952 state.str = str
    954 try:
--> 955     p = _parse_sub(source, state, flags & SRE_FLAG_VERBOSE, 0)
    956 except Verbose:
    957     # the VERBOSE flag was switched on inside the pattern.  to be
    958     # on the safe side, we'll parse the whole thing again...
    959     state = State()

File lib/python3.10/sre_parse.py:444, in _parse_sub(source, state, verbose, nested)
    442 start = source.tell()
    443 while True:
--> 444     itemsappend(_parse(source, state, verbose, nested + 1,
    445                        not nested and not items))
    446     if not sourcematch("|"):
    447         break

File lib/python3.10/sre_parse.py:841, in _parse(source, state, verbose, nested, first)
    838         raise source.error(err.msg, len(name) + 1) from None
    839 sub_verbose = ((verbose or (add_flags & SRE_FLAG_VERBOSE)) and
    840                not (del_flags & SRE_FLAG_VERBOSE))
--> 841 p = _parse_sub(source, state, sub_verbose, nested + 1)
    842 if not source.match(")"):
    843     raise source.error("missing ), unterminated subpattern",
    844                        source.tell() - start)

File lib/python3.10/sre_parse.py:444, in _parse_sub(source, state, verbose, nested)
    442 start = source.tell()
    443 while True:
--> 444     itemsappend(_parse(source, state, verbose, nested + 1,
    445                        not nested and not items))
    446     if not sourcematch("|"):
    447         break

File lib/python3.10/sre_parse.py:550, in _parse(source, state, verbose, nested, first)
    548 this = sourceget()
    549 if this is None:
--> 550     raise source.error("unterminated character set",
    551                        source.tell() - here)
    552 if this == "]" and set:
    553     break

error: unterminated character set at position 17
```

### Additional contract requirements

- In particular, an abbreviation definition containing a backslash must remain plaintext: `*[\\]: Not an abbreviation` must render as `<p>*[\]: Not an abbreviation</p>`.
