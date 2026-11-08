Bug: BitmapEncoder not accepting uppercase format of extension
**Describe the bug**
File extensions with uppercase, eg."image.PNG", are not supported by addFileExtension() method  of BitmapEncoder class.

**To Reproduce**

```
public class BitmapEncoderTest {

    @Test
    public void testAddFileExtension() {
        String fileName1 = "image";
        String fileName2 = "image.png";
        String fileName3 = "image.PNG";

        Assert.assertEquals(BitmapEncoder.addFileExtension(fileName1, BitmapEncoder.BitmapFormat.PNG), "image.png");
        Assert.assertEquals(BitmapEncoder.addFileExtension(fileName2, BitmapEncoder.BitmapFormat.PNG), "image.png");
        Assert.assertEquals(BitmapEncoder.addFileExtension(fileName3, BitmapEncoder.BitmapFormat.PNG), "image.png");
    }
}
```

**Screenshots**
![image](https://github.com/knowm/XChart/assets/42827734/e2d5d12a-0e62-4a3f-b1ed-e4950f5eee56)



**Expected behavior**
The method should accept both lowercase and uppercase formats of a file extension. Eg: "PNG" == "png"

### Additional contract requirements

- When the filename consists only of the selected extension, return that extension in lowercase; for example, `addFileExtension(".bmp", BitmapFormat.BMP)` and `addFileExtension(".BmP", BitmapFormat.BMP)` must both return `.bmp`.
