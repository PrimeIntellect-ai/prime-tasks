Implementation schemas not correctly validating when writing EDI
I'm running validation with the xml stream writer -- but it seem only be validating using the transaction.xml and not the implementation.xml
For example:
I have this in my Transaction.xml
```
                     .....
            <loop code="Loop1000" minOccurs="1" maxOccurs="4" >
                <sequence>
                    <segment type="N1"/>
                    <loop code="Loop1100" maxOccurs="1">
                        <sequence >
                            <segment type="ACT" minOccurs="1" />
                        </sequence>
                    </loop>
                </sequence>
            </loop>
            <loop name="Loop2000"  code="Loop2000" type="Loop2000"  maxOccurs="9999">
                <sequence>
                    <segment type="INS" minOccirs="1"/>
                     .....

```
and i have this, in  my Implementaion.xml (I have a B and C Loop1000 as well.. with a minOccurs=0, the A loop  is the only one required)
```
            <loop  title="Loop1000A" typeId="Loop1000A" code="Loop1000A" type="Loop1000" discriminator="1" minOccurs="1" maxOccurs="1">
                <sequence>
                    <segment type="N1" title="Sponsor Name"  minOccurs="1" description="1000">
                        <sequence>
                            <element position="1" title="Entity Identifier Code (Sponsor)" minOccurs="1">
                                <enumeration>
                                    <value>P5</value>
                                </enumeration>
                            </element>
                            <element position="2" minOccurs="0"/>
                            <element position="3" minOccurs="1"/>
                            <element position="4" minOccurs="1"/>
                        </sequence>
                    </segment>
                </sequence>
            </loop>
```

when I validate my transaction that has the B and C loop -- validation passes ,unexpectedly, since there is no matching 1000A loop.
if I remove the B and C loops as well.. then it fails. Not exactly as expected.. since   I get the error on the next segment
Encountered SEGMENT_ERROR [MANDATORY_SEGMENT_MISSING] in segment INS  --> the INS segment exists, its the first segment after the 1000 loop... it's the Loop1000 that's missing... but at least it fails .

My question is -- should the validation be performed using the implementation schema? Or is my expectation not correct?
Should the validation message indicate that it's the Loop1000 that's missing (as opposed to the INS)?

_Originally posted by @d-floyd in https://github.com/xlate/staedi/discussions/284_

### Additional contract requirements

When validation is performed against an implementation schema, loop-level validation errors reference the loop rather than the encountered segment:

- `IMPLEMENTATION_LOOP_OCCURS_UNDER_MINIMUM_TIMES`: the error's reference code is the implementation loop's code (the implementation loop with code `0000C` yields reference code `0000C`), and the error text is the standard loop code (`L0000`).
- `LOOP_OCCURS_OVER_MAXIMUM_TIMES`: the error's reference code is the loop's code (the implementation loop with code `0000B` yields reference code `0000B`; the standard loop `L0000` yields reference code `L0000`), and the error text is the segment id (`S11`).
