generated XML uses transaction element code instead of implementation element code?
### Discussed in https://github.com/xlate/staedi/discussions/277

<div type='discussions-op-text'>

<sup>Originally posted by **d-floyd** June 16, 2022</sup>
similar to this.. #274
 I've defined a recurring element like this in the implementation xml:
```
                    <segment name="SubscriberIdentifier" typeId="SubscriberIdentifier" code="SubscriberIdentifier" type="REF" maxOccurs="1" discriminator="1">
                        <sequence>
                            <element position="1" title="Identification Qualifier">
                                <enumeration>
                                    <value>0F</value>
                                </enumeration>
                            </element>
                            <element position="2"/>
                        </sequence>
                    </segment>
                    <segment name="MemberPolicy" typeId="MemberPolicy" code="MemberPolicy" type="REF" maxOccurs="1" discriminator="1">
                        <sequence>
                            <element position="1" title="MemberPolicy Qualifier">
                                <enumeration>
                                    <value>1L</value>
                                </enumeration>
                            </element>
                            <element position="2"/>
                        </sequence>
                    </segment>
                    <segment  name="MemberSupplemental" typeId="MemberSupplemental"  code="MemberSupplemental" type="REF" maxOccurs="13" discriminator="1">
                        <sequence>
                            <element position="1" title="MemberPolicy Qualifier">
                                <enumeration>
                                    <value>17</value>
                                    <value>6O</value>
                                </enumeration>
                            </element>
                            <element position="2"/>
                        </sequence>
                    </segment>
```
in the transaction.xml I simply have this..
```
 <segment type="REF" maxOccurs="15" />
```
edi elements input:
```

REF*0F*5272937390~
REF*1L*5272937390~
REF*17*5272937390~
REF*6O*5700456720~
```


I was expecting this:
```
     <s:SubscriberIdentifier>
          <e:REF01>0F</e:REF01>
          <e:REF02>5272937390</e:REF02>
        </s:SubscriberIdentifier>
        <s:MemberPolicy>
          <e:REF01>1L</e:REF01>
          <e:REF02>5272937390</e:REF02>
        </s:MemberPolicy>
        <s:MemberSupplemental>
          <e:REF01>17</e:REF01>
          <e:REF02>5272937390</e:REF02>
        </s:MemberSupplemental>
        <s:MemberSupplemental>
          <e:REF01>6O</e:REF01>
          <e:REF02>5700456720</e:REF02>
        </s:MemberSupplemental>
```

but what I got was this:
```

        <s:REF>
          <e:REF01>0F</e:REF01>
          <e:REF02>5272937390</e:REF02>
        </s:REF>
        <s:REF>
          <e:REF01>1L</e:REF01>
          <e:REF02>5272937390</e:REF02>
        </s:REF>
        <s:REF>
          <e:REF01>17</e:REF01>
          <e:REF02>5272937390</e:REF02>
        </s:REF>
        <s:REF>
          <e:REF01>6O</e:REF01>
          <e:REF02>5700456720</e:REF02>
        </s:REF>
```


Does this not work the same with elements as it does with loops? Or is there something else I need set up?</div>

This is expected, but a configuration option to enable mapping the segment implementation's `code` to the XML element name would be a good enhancement.

cc: @d-floyd

### Additional contract requirements

The option is `EDIInputFactory.XML_USE_SEGMENT_IMPLEMENTATION_CODES` (`io.xlate.edi.stream.XML_USE_SEGMENT_IMPLEMENTATION_CODES`). When enabled, segment elements use the implementation schema segment's `code` as their XML element name. When the option is absent or false, segment elements retain the existing naming behavior, using the transaction schema's segment code.
