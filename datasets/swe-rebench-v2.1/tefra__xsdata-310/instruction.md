xsi:type not working on xsd:anyType elements
I have a use case were we wrap lists of 'items' in an xml where the elements are in the xsd marked as 'xs:anyType'.

The xml though specifies the type with something like:
` xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="api:searchResultItem" `
so, the actual type is specified with an xsi:type attribute.

If I unmarshal this xml with xsdata these object just become `AnyElement`s and are not unmarshaled to the correct type (as e.g. pyxb and jaxb would do).

I don't rule out that I do something wrong, but as far as I looked into the code it is not supported at all. But please  correct me if I'm wrong.
