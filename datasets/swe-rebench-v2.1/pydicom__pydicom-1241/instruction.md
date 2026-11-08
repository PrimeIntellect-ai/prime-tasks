Add support for Extended Offset Table to encaps module
[CP1818](http://webcache.googleusercontent.com/search?q=cache:xeWXtrAs9G4J:ftp://medical.nema.org/medical/dicom/final/cp1818_ft_whenoffsettabletoosmall.pdf) added the use of an Extended Offset Table for encapsulated pixel data when the Basic Offset Table isn't suitable.

### Additional contract requirements

- Add a public function `encapsulate_extended(frames)` in the `pydicom.encaps`
  module. It returns a 3-tuple of `bytes`: the encapsulated Pixel Data, an
  Extended Offset Table containing the little-endian unsigned 64-bit byte
  offset of each frame, and an Extended Offset Table Lengths containing the
  little-endian unsigned 64-bit size of each frame. It must produce these
  tables for frame data whose total size exceeds the Basic Offset Table limit.
- `encapsulate(frames, has_bot=True)` in `pydicom.encaps` raises `ValueError`
  when the total encapsulated frame data would exceed the Basic Offset Table
  limit of 2**32 - 1 bytes. For a total of 4294967296 bytes the message begins
  `The total length of the encapsulated frame data (4294967296 bytes) will be greater than the maximum allowed by the Basic `.
