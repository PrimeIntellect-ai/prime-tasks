NullPointerException on KDOC inspection
```
package test.paragraph3.trailing_comma

class Customer(
    val name: String,
    lastName: String,
)

fun shift(x: Int,
          y: Int,
) {
    shift(
        25,
        20,
    )

    val colors = listOf(
        "red",
        "green",
        "blue",
    )
}

fun getZValue(mySurface: Surface,
              xValue: Int,
              yValue: Int,
) =
    mySurface[
            xValue,
            yValue
    ]

fun isReferenceApplicable(myReference: KClass<*>,
) = when (myReference) {
    Comparable::class,
    Iterable::class,
    String::class,
    -> true
    else -> false
}

fun isReferenceApplicable(myReference: KClass<*> ,// comment
) = when (myReference) {
    Comparable::class,
    Iterable::class,
    String::class,
    -> true
    else -> false
}

@ApplicableFor([
    "serializer",
    "balancer",
    "database",
    "inMemoryCache",
],
)
fun foo() {}

fun <T1,
        T21,
        > foo() {}

fun mains() {
    foo<
            Comparable<Number,
                    >,
            Iterable<Number,
                    >,
            >()
}

fun printMeanValue() {
    var meanValue: Int = 0
    for ((
        _,
        _,
        year,
    ) in cars) {
        meanValue += year
    }
    println(meanValue/cars.size)
}

enum class SomeEnum(
    val a: Int, val b: Int  ,// comment
)

enum class SomeEnum(
    val a: Int, val b: Int,// comment
)

enum class SomeEnum(
    val a: Int, val b: Int  ,/* comment */
)

enum class SomeEnum(
    val a: Int, val b: Int,  /**
    some comment */
)

fun foo() {
    val sum: (Int, Int, Int,) -> Int = fun(
        x,
        y,
        z ,// trailing comma
    ): Int {
        return x + y + x
    }
    println(sum(8, 8, 8))
}

fun shift(x: Int, y: Int) {
    shift(
        25,
        20, // trailing comma
    )

    val colors = listOf(
        "red",
        "green",
        "blue", // trailing comma
    )
}
```

<img width="1205" alt="image" src="https://user-images.githubusercontent.com/58667063/171022032-4fd59843-84d8-4e0c-9486-d03597e72184.png">


Diktat incorrectly treats KDOC and causes hard failure

### Additional contract requirements

- Diktat must process Kotlin source that contains an anonymous function expression without a hard failure. An anonymous function expression itself does not require KDoc.
