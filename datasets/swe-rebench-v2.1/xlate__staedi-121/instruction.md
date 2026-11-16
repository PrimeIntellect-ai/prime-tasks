Elements of improperly sequenced elements are not reset
If a segment appears out of sequence in a loop and the segment has already appeared earlier in the loop, the elements of the additional occurrence are not reset before validation. This results in element occurrence errors in addition to the (correct) segment occurrence error for the improperly sequenced segment.
