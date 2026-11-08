How to stop outline from showing
Since the librabry has no api for checking if outline is shown. I use my own variable to control it.

I initial the instance like this:
~~~~~
this.hw = HanziWriter.create('character-target-div', this.strArray[this.j], {
      width: 280,
      height: 280,
      padding: 10,
      strokeColor: '#000000',
      outlineColor: '#ec7063',
      showHintAfterMisses: 1,
      highlightColor: '#0000FF',
      charDataLoader: function (char) {
        const loadedData = require(`hanzi-writer-data/${char}`);
        return loadedData;
      },
~~~~
So by default, outline  is shown. That's good. I offer a button to switch it off like this:
~~~~
toggleOutline() {
    if (this.hw) {
      this.isOutlineHidden = !this.isOutlineHidden;
      if (this.isOutlineHidden) {
        this.hw.hideOutline()
      } else {
        this.hw.showOutline();
      }

    }
  }
~~~~
However, after loading a new character, the outline is shown again. but I'd like to keep it off, so I did it like this:
~~~~
this.hw.setCharacter(this.strArray[this.j]);
        if (this.isOutlineHidden) {
          this.hw.hideOutline();
        }
        this.hw.quiz();
~~~~

It worked but the outline showed for around half second before it's hidden again. How to avoid that?
thx.

### Additional contract requirements

- After `hideOutline()` has been called, a subsequent call to `setCharacter(char)` must keep the outline hidden throughout the character change, including while character data is loading and the new character is rendered. Once the new character has loaded and rendered, the outline opacity must be `0` without requiring another call to `hideOutline()`.
