[WW3] sub-string of character string causes crash
Asif has reported that the WW3 code uses a character variable:

      CHARACTER(256)          :: LINE, TEST
    100 CONTINUE
      ! read line
      READ ( NDSI, 900, END=800, ERR=801, IOSTAT=IERR, IOMSG=MSG ) LINE
      ! leading blanks removed and placed on the right
      TEST = ADJUSTL ( LINE )
      IF ( TEST(1:1).EQ.CHCKC .OR. LEN_TRIM(TEST).EQ.0 ) THEN

and PSyclone falls over in `ArrayMixin.is_lower_bound` when examinging `TEST(1:1)` [HIDDEN] (because we don't support Character variables).

### Additional contract requirements

- A character substring such as `TEST(1:1)` must not cause `is_lower_bound` to crash. If its lower-bound status cannot be established, `is_lower_bound` must return false.
