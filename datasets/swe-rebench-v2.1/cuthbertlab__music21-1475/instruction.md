Regression issue - unable get fingering of cords after parsing xml file
<!-- Version of music21:  print(music21.__version__) -->
**music21 version**

Issue on version `8.1.0`   <!-- replace with actual version -->
Working well on version `7.3.3`


**Problem summary**
<!-- Briefly: what undesired thing happens when what action is taken? -->
**Regression issue unless there is a new way, I didn't find out.**
Unable get all fingering of chord, I'm receiving only the first finger

![image](https://user-images.githubusercontent.com/16102210/198280635-565c74ca-770f-49ca-be76-204dde5574f6.png)


**Steps to reproduce**

Use the following code and the attached file (simple cord)


```
for generalNote in music21.converter.parse(f"myFile.xml").parts[0].flat.notes:
  fingers = []

  # On version 8.1.0 print "generalNote.articulations.size: 1"
  # On version 7.3.3 print "generalNote.articulations.size: 3"
  print(f"generalNote.articulations.size: {len(generalNote.articulations)}")

  for articulation in (generalNote.articulations):
    if isinstance(articulation, music21.articulations.Fingering):
      fingers.append(articulation.fingerNumber)

  # fingers contain 1 finger on verion 8.1.1 and 3 fingers on version 7.3.3

```


**Expected vs. actual behavior**
<!-- Consider annotating the output produced by a function -->
Actual getting 1 finger
Expected getting 3 fingers

**More information**
<!-- If relevant: OS, suggested fix, attempted workarounds -->

<!-- Note: only Mac and Windows are directly supported by music21 staff.
     Bug reports that are specific to other OSes w/o a PR will be closed
     unless the reporter is willing to contribute a fix.
 -->
