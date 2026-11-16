Wish list: aux tag iterator API
(Put here simply so we don't forget it.)

The (now merged) Samtools PR https://github.com/samtools/samtools/pull/516 copies over the `aux_type2size` and `skip_aux` functions as it has a mechanism of iterating through the tag list.

Something akin to these functions ought to be public, although perhaps not these explicit interfaces.  I think a more iterator focused approach would work.  Eg in a similar fashion to kstring initialisations:

```
bam_tag_iter_t it = BAM_TAG_ITER_INITIALIZE;  // or bam_tag_iter_initialize(&it) if we want it opaque.
uint8_t *tag;
while ((tag = bam_aux_next(b, &it))) {
    // do stuff
}
```

The tag initialise function just nulls the contents.  The `bam_aux_next` function skips to the next tag, or identifies the first one if the pointer hasn't been set.  The BAM data end pointer from `skip_aux` can be internalised into the data type and hidden from the user.   Alternatively we just expose `skip_aux` as it is now and have an `aux_end` function to avoid the mess of grubbing through `b->data + b->l_data` internals.

`aux_type2size` may be useful as-is, as we already have search functions so being able to return how big it is would be helpful for more than this case.  However it could be renamed perhaps - maybe `bam_aux_size`.

### Additional contract requirements

Expose `bam_aux_first(const bam1_t *b)` to begin a scan and `bam_aux_next(const bam1_t *b, const uint8_t *s)` to advance it. Each returns a pointer to an auxiliary field, and returns `NULL` when there is no field to return. Starting with the first-field function and repeatedly advancing must permit callers to visit all auxiliary fields in record order without inspecting the record's internal auxiliary-data end pointer. The pointer returned for a field addresses its type byte; its two tag bytes immediately precede it.
