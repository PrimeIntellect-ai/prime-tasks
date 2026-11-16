[WW3] sub-string of character string causes crash
Asif has reported that the WW3 code uses a character variable:

      CHARACTER(256)          :: LINE, TEST
    100 CONTINUE
      ! read line
      READ ( NDSI, 900, END=800, ERR=801, IOSTAT=IERR, IOMSG=MSG ) LINE
      ! leading blanks removed and placed on the right
      TEST = ADJUSTL ( LINE )
      IF ( TEST(1:1).EQ.CHCKC .OR. LEN_TRIM(TEST).EQ.0 ) THEN

and PSyclone falls over [HIDDEN] when examinging `TEST(1:1)` [HIDDEN]

### Additional contract requirements

- Processing a character substring such as `TEST(1:1)` must not crash PSyclone when its type information is unsupported.
