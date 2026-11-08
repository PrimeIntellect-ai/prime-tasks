Using `bgzf_read_small()` breaks subsequent `bgzf_useek()` calls
PR #1772 added a simplified inline version of `bgzf_read()` that uses inline code when the request can be satisfied directly from the buffer, otherwise punts to the real `bgzf_read()`. Very laudable. However I encountered seek problems when using it.

I rederived the inline function by starting with the code of the full `bgzf_read()`, assuming the invariant that `length < fp‑>block_length - fp‑>block_offset`, and simplifying the code accordingly. I ended up with a function that is fairly similar to `bgzf_read_small()` as added to _htslib/bgzf.h_ but with some additions:

```diff
static inline ssize_t bgzf_read_small(BGZF *fp, void *data, size_t length) {
     // A block length of 0 implies current block isn't loaded (see
     // bgzf_seek_common).  That gives negative available so careful on types
     if ((ssize_t)length < fp->block_length - fp->block_offset) {
         // Short cut the common and easy mode
         memcpy((uint8_t *)data,
                (uint8_t *)fp->uncompressed_block + fp->block_offset,
                length);
         fp->block_offset += length;
+
+        // For raw gzip streams this avoids short reads.
+        if (fp->block_offset == fp->block_length) {
+            fp->block_address = bgzf_htell(fp);
+            fp->block_offset = fp->block_length = 0;
+        }
+
[HIDDEN]
+
         return length;
     } else {
         return bgzf_read(fp, data, length);
     }
 }
```

[HIDDEN] subsequent `bgzf_useek()` calls may jump to the wrong location. [HIDDEN]

The `if` block looks harder to deal with, because it calls `bgzf_htell()` which is private within _bgzf.c_. However it turns out that the invariant implies that this `if` will never be true, so in fact I should have simplified it away to nothing too. Phew.

[HIDDEN]

(I have not analysed `bgzf_write_small()` to see if it has any similar infelicities.)

### Additional contract requirements

- After a successful `bgzf_read_small()` fast-path read, a subsequent `bgzf_useek()` must seek to the correct logical file position.
