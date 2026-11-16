リンクのtargetを可視化する
新しいウインドウ/タブが開くことをテキストやアイコン等で表示している場合があるが、それが徹底できているかをリンクをクリックせずに判断したい（Webサイト内で、新しいウィンドウ/タブが開くリンクで、そういったテキストやアイコンがあるものと無いものが混在することが無いようにしたい）

a要素に対してtarget属性の値を表示することができるとよさそう

### Additional contract requirements

- For an `<a>` element with a `target` attribute, the returned tip must have `type: "linkTarget"` and `content` equal to the attribute value.
