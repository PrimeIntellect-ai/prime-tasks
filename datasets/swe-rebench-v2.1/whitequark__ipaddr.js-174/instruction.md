Some IPv4 Mapped IPv6 Addresses don't parse
The following calls throw exceptions:

ipaddr.IPv6.parse("FFFF::255.255.255.255")
throw :
Error: ipaddr: the address has neither IPv6 nor IPv4 format

but
ipaddr.IPv6.parser("FFFF::0:255.255.255.255") is ok!


![QQ图片20231007143751](https://github.com/whitequark/ipaddr.js/assets/7478660/d0443f6f-4b0f-40d4-a7fc-7cf0cc07dffc)


I'm using version 2.1.0
