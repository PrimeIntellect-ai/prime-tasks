Wildcard imports break Anvil codegen annotation constant resolution
Given the following:

    package org.bubenheimer.anvilbugs.constants

    const val MY_CONST: String = "Hi"

and

    package org.bubenheimer.anvilbugs

    import org.bubenheimer.anvilbugs.constants.*
    import javax.inject.Inject
    import javax.inject.Named

    class MyClass {
        @Inject
        @Named(MY_CONST)
        lateinit var myString: String
    }

Anvil 2.4.0 generates the invalid code below, which references the constant from the wrong package (`org.bubenheimer.anvilbugs.MY_CONST` instead of `org.bubenheimer.anvilbugs.constants.MY_CONST`):

    public class MyClass_MembersInjector(
        private val myString: Provider<String>
    ) : MembersInjector<MyClass> {
        public override fun injectMembers(instance: MyClass): Unit {
            MyClass_MembersInjector.injectMyString(instance, myString.get())
        }

        public companion object {
            @JvmStatic
            public fun create(myString: Provider<String>): MyClass_MembersInjector =
                MyClass_MembersInjector(myString)

            @JvmStatic
            @InjectedFieldSignature("org.bubenheimer.anvilbugs.MyClass.myString")
            @Named(value = org.bubenheimer.anvilbugs.MY_CONST)
            public fun injectMyString(instance: MyClass, myString: String): Unit {
                instance.myString = myString
            }
        }
    }
