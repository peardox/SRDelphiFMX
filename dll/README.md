# dll

`LenticularBridge.dll` goes here. Building the bridge (`bridge/`, see the main README) copies it here automatically. After each build, every Delphi project's post-build step copies it next to the executable.

`.gitignore` excludes `*.dll`, so a newly built bridge is committed on purpose with `git add -f dll/LenticularBridge.dll`; this README keeps the folder in the repository either way.
