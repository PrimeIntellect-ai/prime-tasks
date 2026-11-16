TOC:Anchor link written in Japanese does not work
I'm using the extension TOC with slugify_unicode for Japanese.
And I'm using anchor links.
In some cases, Japanese anchor link does not work.
That is when Japanese characters contains dakuon(for example 'ba')
or handakuon(for example 'pa').
I think this is because the characters in the generated ID
and the characters in the header are different.

Sample Markdown:

```
[TOC]
[anchor link to プログラム](#プログラム)
[anchor link to ぷろぐらむ](#ぷろぐらむ)

##プログラム

##ぷろぐらむ
```

Generated html:
```
<div class="toc">
<ul>
<li><a href="#フロクラム">プログラム</a></li>
<li><a href="#ふろくらむ">ぷろぐらむ</a></li>
</ul>
</div>
<p><a href="#プログラム">anker link to プログラム</a><br />
<a href="#ぷろぐらむ">anker link to ぷろぐらむ</a>  </p>
<h2 id="フロクラム">プログラム</h2>
<h2 id="ふろくらむ">ぷろぐらむ</h2>

```

The result I expect is:
```
<div class="toc">
<ul>
<li><a href="#プログラム">プログラム</a></li>
<li><a href="#ぷろぐらむ">ぷろぐらむ</a></li>
</ul>
</div>
<p><a href="#プログラム">anker link to プログラム</a><br />
<a href="#ぷろぐらむ">anker link to ぷろぐらむ</a>  </p>
<h2 id="プログラム">プログラム</h2>
<h2 id="ぷろぐらむ">ぷろぐらむ</h2>
```
As far as I can tell, this depends on how the unicodedata.normalize()
method arguments are used.
[HIDDEN]

Reference: [Difference Between NFD, NFC, NFKD, and NFKC Explained with Python Code | by Xu LIANG | Towards Data Science][reference1]

I'm not familiar with unicode.
And this is my first post.
Please investigate.

[reference1]:https://towardsdatascience.com/difference-between-nfd-nfc-nfkd-and-nfkc-explained-with-python-code-e2631f96ae6c
