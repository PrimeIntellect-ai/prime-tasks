Statement after return executed
function f() {
    return (() => 1)();
    display("here");
}
f();

currently displays "here"
