module ss13.exports;

import std.conv;
import std.range;
import byond;
import ss13.atmos.gas;

mixin ByondFunction!("TestFunc", (string arg) {
    return arg;
});


mixin ByondFunction!("MyFunc", (string header, int repCount, string repeatWhat) {
    return header ~ ": " ~ repeatWhat.repeat(repCount).join(", ");
});

