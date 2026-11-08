DPT 7.* and 8.* should consider resolution
**Description of problem:**
For a number of less frequently used data point types, the numeric content is not displayed/converted correctly. I noticed this because my smart meter displays an unbalanced load (DPT 8.010) that is too high by a factor of 100.

Specifically, these are DPT 7.* and 8.*, which have a resolution other than 1 as specified in the KNX standard. Here the unsigned number must be multiplied accordingly, otherwise the display will not be correct:

- 7.003 time_period_10msec
- 7.004 time_period_100msec
- 8.003 delta_time_10ms
- 8.004 delta_time_100ms
- 8.010 percentV16

This behaviour is specified in the KNX standard (03_07_02 Datapoint Types v01.08.02 AS.pdf, Sections 3.8 and 3.9.)

- [ ] using xknx standalone
- [X] using Home-Assistant knx integration

**Version information:**
- xknx / Home-Assistant release with the issue: 2024.6.4
- last working xknx / Home-Assistant release (if known): none

**KNX installation:**
(Mind the German locale)
- ETS 5.7.7 displays the DPT 8.010 value correctly as: "Prozentdifferenz (%) 0B BC | 30,04 %"
- In HomeAssistant, the corresponding percentV16 value appears as: "3.004 %"
