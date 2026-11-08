@echo off
rem PasDoc reference of the Lenticular units (glasses-free 3D from Delphi),
rem as HTML and as HTML Help (.chm), one set for the API and one per program:
rem   docs\html\api            HTML: the shared units in lib (the API)
rem   docs\chm\api             HTML Help as docs\html\api, compiled to a .chm
rem   docs\html\<program>      HTML: one program (LenticularDemoFMX, LenticularDemoVCL,
rem                            MoviePlayerFMX, ...): its .dpr, its forms and
rem                            the lib units it uses
rem   docs\chm\<program>       HTML Help as docs\html\<program>, as a .chm
rem
rem The programs are found, not listed: every folder in the root holding
rem <folder>\<folder>.dpr is one. What each program's reference holds is read
rem from its .dpr's uses clause (the units named "in '...'"): its forms, and
rem the units from ..\lib, so a new program, form or lib unit is picked up
rem without changing this script. Units from elsewhere (the FastMM5
rem submodule) are left out. The api run takes every unit in lib except
rem Lenticular.StereoViewport.Reg, which is design-time registration, not API.
rem
rem Needs pasdoc on the PATH (or set PASDOC=full path). The .chm files need
rem Microsoft HTML Help Workshop's hhc.exe (set HHC=full path if it is not
rem in the default folder); without it the HTML Help projects are written
rem but not compiled. Run from anywhere; the output folders are git-ignored.
rem docs\html and docs\chm are deleted first, with everything in them, so no
rem page of an earlier run (or of a program since removed) is left behind;
rem nothing else in docs\ is touched.
rem
rem Dark colours: after each run, tools\pasdoc-dark.css (HTML: dark only when
rem the browser or system asks for it) or tools\pasdoc-chm-dark.css (HTML
rem Help: always dark, as the viewer cannot ask) is appended to the
rem pasdoc.css that PasDoc wrote, so PasDoc's own stylesheet stays as it is
rem and no copy of it is kept here. Set PASDOC_DARK=0 to leave them out.
rem
rem Defines: PasDoc defines no platform symbols itself, so the Win64 view is
rem chosen here (the only one there is: the display runtime is 64-bit only).
rem FastMM_FullDebugModeWhenDLLAvailable is left undefined, the Release view
rem of the .dpr files. The ffmpeg-headers units are named in Lenticular.VideoDecoder's
rem uses clause but never parsed.

setlocal
cd /d "%~dp0.."

if "%PASDOC%"=="" set PASDOC=pasdoc

rem pasdoc installed? (a full path in PASDOC, or a program on the PATH)
set FOUND=0
if exist "%PASDOC%" set FOUND=1
if %FOUND%==0 where "%PASDOC%" >nul 2>&1 && set FOUND=1
if %FOUND%==0 (
  echo pasdoc was not found ^(looked for: %PASDOC%^).
  echo Install it from https://github.com/pasdoc/pasdoc/releases/
  echo ^(download the archive for Windows, unpack it and put its bin folder on the PATH,
  echo or set PASDOC=full path of pasdoc.exe before running this script^)
  endlocal & exit /b 1
)

if "%HHC%"=="" set HHC=%ProgramFiles(x86)%\HTML Help Workshop\hhc.exe

set COMMON=--define PASDOC --define MSWINDOWS --define WIN64 --define CPUX64 --include lib --visible-members protected,public,published,automated --inherited-members default-hide --write-uses-list --verbosity 3
set SUBTITLE=glasses-free 3D from Delphi

set FAILED=0
set RUNS=0

rem The API: every unit in lib except the design-time registration
set APISRC=
for %%F in (lib\*.pas) do call :addapi "%%F"

rem The programs: every <folder>\<folder>.dpr in the root
set APPS=
for /d %%D in (*) do if exist "%%D\%%D.dpr" call :addapp %%D

echo ==== Programs found:%APPS%
echo ==== Cleaning the output folders
call :clean docs\html
call :clean docs\chm

call :run html api docs\html\api --name Lenticular --title "Lenticular API - %SUBTITLE%" %APISRC%
call :run htmlhelp api docs\chm\api --name Lenticular --title "Lenticular API - %SUBTITLE%" %APISRC%
for %%A in (%APPS%) do call :program %%A

call :chm docs\chm\api
for %%A in (%APPS%) do call :chm docs\chm\%%A

echo.
if %FAILED%==0 (echo PasDoc: all %RUNS% runs finished; start at docs\html\api\index.html) else (echo PasDoc: %FAILED% step^(s^) FAILED - see above)
endlocal & exit /b %FAILED%

rem ---- :addapi <lib\unit.pas> - adds one lib unit to the api run, unless it
rem      is a design-time registration unit (*.Reg.pas)
:addapi
set "UNITNAME=%~n1"
if /i "%UNITNAME:~-4%"==".Reg" exit /b 0
set APISRC=%APISRC% "%~1"
exit /b 0

rem ---- :addapp <folder> - adds one program folder to the list
:addapp
set APPS=%APPS% %1
exit /b 0

rem ---- :program <folder> - HTML and HTML Help runs for one program: its
rem      .dpr, plus each unit its uses clause names "in '...'"
:program
set APP=%~1
set SRCS="%APP%\%APP%.dpr"
for /f "usebackq tokens=2 delims='" %%P in (`findstr /l /c:" in '" "%APP%\%APP%.dpr"`) do call :addsrc %APP% "%%P"
call :run html %APP% docs\html\%APP% --name %APP% --title "%APP% - %SUBTITLE%" %SRCS%
call :run htmlhelp %APP% docs\chm\%APP% --name %APP% --title "%APP% - %SUBTITLE%" %SRCS%
exit /b 0

rem ---- :addsrc <folder> <path from the .dpr> - adds one unit of a program:
rem      ..\lib\X.pas as lib\X.pas; ui\X.pas (inside the program's folder) as
rem      <folder>\ui\X.pas; anything else outside the folder is left out
:addsrc
set "SRC=%~2"
if /i "%SRC:~0,7%"=="..\lib\" set SRCS=%SRCS% "%SRC:~3%"
if /i "%SRC:~0,7%"=="..\lib\" exit /b 0
if "%SRC:~0,3%"=="..\" exit /b 0
set SRCS=%SRCS% "%~1\%SRC%"
exit /b 0

rem ---- :clean <folder> - deletes one output folder with everything in it
:clean
if not exist "%~1\" (
  echo %1: not there yet
  exit /b 0
)
rmdir /s /q "%~1"
if exist "%~1\" (
  echo %1: could NOT be deleted completely - is a file in it open ^(browser, .chm viewer^)?
  set /a FAILED+=1
) else (
  echo %1: deleted
)
exit /b 0

rem ---- :run <format> <label> <output folder> <name, title and sources...>
:run
set FMT=%1
set LABEL=%2
set OUT=%3
shift & shift & shift
set ARGS=
:collect
if "%~1"=="" goto collected
set ARGS=%ARGS% %1
shift
goto collect
:collected
echo.
echo ==== PasDoc %FMT% (%LABEL%) -^> %OUT%
if not exist "%OUT%" mkdir "%OUT%"
set /a RUNS+=1
"%PASDOC%" --format %FMT% --output %OUT% %COMMON% %ARGS%
if errorlevel 1 (echo ==== PasDoc %FMT% %LABEL% FAILED & set /a FAILED+=1 & exit /b 0)
call :dark %FMT% %OUT%
exit /b 0

rem ---- :dark <format> <output folder> - appends the dark colours for that
rem      format to the pasdoc.css PasDoc wrote there
:dark
if "%PASDOC_DARK%"=="0" exit /b 0
set DARKCSS=tools\pasdoc-dark.css
if /i "%~1"=="htmlhelp" set DARKCSS=tools\pasdoc-chm-dark.css
if not exist "%DARKCSS%" (
  echo ==== %DARKCSS% not found - %~2 left in PasDoc's own colours
  set /a FAILED+=1
  exit /b 0
)
if not exist "%~2\pasdoc.css" (
  echo ==== %~2\pasdoc.css not found - dark colours not added
  set /a FAILED+=1
  exit /b 0
)
(echo.& type "%DARKCSS%") >> "%~2\pasdoc.css"
echo ==== Dark colours from %DARKCSS% added to %~2\pasdoc.css
exit /b 0

rem ---- :chm <folder> - compiles the HTML Help project PasDoc wrote there
:chm
if not exist "%HHC%" (
  echo ==== %1: hhc.exe not found at "%HHC%" - .hhp written, .chm not compiled
  exit /b 0
)
for %%F in ("%~1\*.hhp") do (
  echo ==== Compiling %%F
  "%HHC%" "%%F"
  rem hhc.exe exits with 1 on SUCCESS and 0 on failure
  if not errorlevel 1 (echo ==== %%F: .chm NOT compiled & set /a FAILED+=1)
)
exit /b 0
