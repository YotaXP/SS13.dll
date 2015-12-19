@echo off
set dllName=SS13
set dmdPath=dmd

setlocal EnableDelayedExpansion
SET source=
FOR /R %%G IN (*.d) DO SET source=!source! "%%G"

echo Building %dllName%.dll in Debug mode
%dmdPath% %source% -shared -of"..\%dllName%.dll" -g -debug
if errorlevel 1 goto reportError

del ..\%dllName%.obj

goto done
:reportError
echo Build failed...
:done
