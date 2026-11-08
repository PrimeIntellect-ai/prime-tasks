[BUG] IPv6 Shortening is not right
the below toString() operation is wrong.

> ipaddr.parse("2001:0000:0000:0db8:0000:0000:0000:0001").toString();
'2001::db8:0:0:0:1'  --> This format is not the right one

rfc5952: https://www.rfc-editor.org/rfc/rfc5952.txt

4.2.3. Choice in Placement of "::"

When there is an alternative choice in the placement of a "::", the **longest run of consecutive 16-bit 0 fields MUST be shortened** (i.e., the sequence with three consecutive zero fields is shortened in 2001:0:0:1:0:0:0:1). When the length of the consecutive 16-bit 0 fields are equal (i.e., 2001:db8:0:0:1:0:0:1), the first sequence of zero bits MUST be shortened. For example, 2001:db8::1:0:0:1 is correct representation.

So in our case,
IPv6: 2001:0000:0000:0db8:0000:0000:0000:0001
The right shortened representation should have been: 2001:0:0:db8::1
