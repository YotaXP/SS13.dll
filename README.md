# SS13.dll

## Oh my god what is this?

A place to write native code that would be too slow to run in DM.

## Why D?

Because I'm a hipster.

## How do I work with these files?

I expect the project layout to change before incorporation into the /tg/station codebase, but for now...

### Building and Debugging the DLL with Visual Studio

- Install [DMD](http://dlang.org/download.html)
 - Verify that the binaries are on your system PATH
- Install [Visual Studio 2015](https://www.visualstudio.com/en-us/downloads/download-visual-studio-vs.aspx) (Community or better)
- Install the [VisualD](https://rainers.github.io/visuald/visuald/StartPage.html) package.
- Download the [Gazoot.var_dump](http://www.byond.com/developer/Gazoot/var_dump) library.
- Open and compile `AtmosDllTest.dme` from Dream Maker
- Open `SS13.dll_src\SS13.dll.sln`
- Open the project properties (Select it in the Solution Explorer and press Alt+Enter)
- Under 'Configuration Properties' -> 'Debugging'
  - Set Command to: `C:\Program Files (x86)\BYOND\bin\dreamseeker.exe` (or werever you have it installed)
  - Set Command Arguments to: `AtmosDllTest.dmb`
  - Set Working Directory to: `..`
- You should now be able to debug the code using breakpoints and all with F5.

### Building the DLL without Visual Studio

- Install [DMD](http://dlang.org/download.html)
 - Verify that the binaries are on your system PATH
- Download the [Gazoot.var_dump](http://www.byond.com/developer/Gazoot/var_dump) library.
- Open and compile `AtmosDllTest.dme` from Dream Maker
- Run `SS13.dll_src\buildWin_debug.bat`
- Run `AtmosDllTest.dmb`
- No debugging for you!

The DM code is currently written to copy `SS13.dll` to `CopySS13.dll` at launch in order to let you easily rebuild the DLL
while the world is running.  You can then reboot the world to bring in the updated DLL.