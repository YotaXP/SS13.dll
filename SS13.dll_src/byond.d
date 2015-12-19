module byond;
import std.json;

char* _byondFunctionAdapter(R, F...)(int argc, char** argv, R function(F) func) if(is(R : string) || is(R == void) || is(R == JSONValue)) {
    import std.string;
    import std.conv;
    import std.utf;

    enum successPrefix = ""; //"\x06"; // ACK - Successful calls return this, followed by the return value of the function.
    enum errorPrefix   = "\x15"; // NAK - Failed calls return this, followed by the exception message.
    string result;
    try {
        if (F.length != argc)
            result = format(errorPrefix ~ "Expected %d arguments.", F.length);
        else {
            F args;
            foreach(i, T; F) // Statically unfold the following code for each type in the type tuple F. (Each argument of the function.)
                static if(is(T == string))
                    args[i] = to!string(argv[i]); // Convert from char* to string
                else
                    args[i] = to!T(to!string(argv[i])); // Convert from char* to string to T
            static if(is(R == void)) {
                func(args);
                result = successPrefix;
            }
            else static if(is(R == JSONValue)) {
                func(args);
                result = successPrefix ~ func(args).toString(JSONOptions.specialFloatLiterals);
            }
            else if(is(R == string))
                result = successPrefix ~ func(args);
            else
                assert(0, "BYOND functions must return 'string', 'JSONValue', or 'void'.");
        }
    }
    catch(Exception e)
        result = errorPrefix ~ e.prettyError;
    catch(Error e)
        result = errorPrefix ~ e.prettyError;
    catch
        result = errorPrefix ~ "Unknown exception.";

    return toUTFz!(char*)(result); // Convert string to char*
}

string prettyError(Throwable t) {
    import std.format, std.traits; //core.exception.RangeError@atmos\gas.d(186): Range violation
    string pretty = format("%s@%s(%d): %s", t.classinfo.name, t.file, t.line, t.msg);
    if (t.next) pretty ~= "\n - " ~ prettyError(t.next);
    return pretty;
}

mixin template ByondFunction(string name, alias func) {
    import std.format;

    pragma(mangle, name) extern(C) export char* _ExportedFunction(int argc, char** argv) {
        return _byondFunctionAdapter(argc, argv, func);
    }
}


string list2params(string[string] list) {
    import std.string, std.uri, std.algorithm;
    return list.byKeyValue().map!((item) => item.key.encode ~ "=" ~ item.value.encode).join("&");
}

string[string] params2list(string params) {
    import std.algorithm;
    string[string] list;
    foreach(item; params.splitter!"a == '&' || a == ';'") {
        immutable sp = item.findSplit("=");
        list[sp[0]] = sp[2] ? sp[2] : "";
    }
    return list;
}

import core.sync.mutex;
__gshared string[] logBacklog = [];
__gshared Mutex logMutex;

void LogDebug(Args...)(string fmt, Args args) {
    import std.format;
    if (!logMutex) logMutex = new Mutex();
    synchronized (logMutex)
        if (logBacklog.length < 50) // Temporary.  Find a smarter way to handle floods.
            logBacklog ~= format(fmt, args);
}

mixin ByondFunction!("GetDebugLog", () {
    import std.string;
    if (!logMutex) logMutex = new Mutex();
    synchronized (logMutex)
        if (logBacklog.length > 0) {
            const logCopy = logBacklog;
            logBacklog = [];
            return logCopy.join("\n");
        }
        else return "";
});
