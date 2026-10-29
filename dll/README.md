# dll

`SRFmxBridge.dll` goes here. Building the bridge (`bridge/`, see the main README) copies it here automatically. After each build, every Delphi project's post-build step copies it next to the executable.

`.gitignore` excludes `*.dll`, so the compiled file isn't committed; this README keeps the folder in the repository.
