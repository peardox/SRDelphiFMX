# Credits and licences

The repository has no licence file of its own yet. GDEM uses MIT, and so could this: everything below allows it, except FastMM5's free licence (see note 1).

Everything listed here belongs to others and keeps its own terms.

| What | Used for | Where | Licence | What it asks of us |
|---|---|---|---|---|
| **Simulated Reality SDK** 1.34.5 (Leia, Inc.) | The C API translated in `lib/SimulatedReality.Api.pas`; the headers the bridge is built against | Not in the repository; `LEIASR_SDKROOT` points at it when building the bridge | MIT-style, Copyright 2025 Leia, Inc.; its third-party parts (ASIO, OpenCV and others) list their own licences in the SDK's `License.txt` | Keep Leia's copyright and licence notice with copies of the SDK's code. The bridge copies none of it, only includes its headers. |
| **SR Platform runtime** (Leia, Inc.) | Eye tracking and weaving at run time (`SimulatedReality*.dll`, the SR service) | Installed on the user's computer with the display's software; never shipped by us | Leia's | Nothing: the runtime is not distributed by us |
| **Delphi Neon** (Paolo Rossi) | Reading and writing `settings.json` (`lib/SRSettings.pas`) | `delphi-neon/` (submodule) | MIT, Copyright (c) 2015 Paolo Rossi | Keep its copyright and licence notice |
| **FastMM5** (Pierre le Riche) | The memory manager, with full debug mode and leak reports in Debug builds | `FastMM5/` (submodule); linked into SRDemoFMX | Dual: GPL v3 at no cost, or a commercial licence | Note 1 |
| **Test images** in `media/` | Testing the weaving with known-good stereo pictures | `media/` | Supplied by the owner; sources not recorded here | Note 2 |
| **FFmpeg** 8.x, GPL shared build | Decoding films in MoviePlayerFMX (`avcodec`, `avformat`, `avutil`, `swscale`, `swresample`) | Not in the repository: each developer puts the DLLs in `dll/ffmpeg/`; the build copies them beside MoviePlayerFMX.exe | GPL (the build includes GPL parts) | Note 3 |
| **FFmpeg Delphi/Pascal headers** 8.1 (DelphiFFmpeg.com, part of FFVCL) | The Pascal declarations of FFmpeg's C API | `ffmpeg-headers/` | BSD-style, Copyright (c) 2008-2026 DelphiFFmpeg.com: see `ffmpeg-headers/LICENSE.txt` | Keep its copyright notice and licence with the source, and reproduce them in documentation of binaries. Changed only by marking every import `delayed`. Not CC0, as first thought. |
| **Big Buck Bunny** (Blender Foundation) | `media/hsbs/BigBuckBunny.hsbs.jpg`: one frame (at 6 s) of a half side-by-side extract of the stereo version, for testing MoviePlayerFMX | `media/hsbs/` | Creative Commons Attribution 3.0 | Credit it: (c) copyright 2008, Blender Foundation, www.bigbuckbunny.org |

## Notes

1. **FastMM5 and the GPL.** FastMM5 is free under the GPL v3, but a program built with it may then only be given out under the GPL. A commercial licence is sold per developer, so the one planned for GDEM would cover this project too. Until then, don't give SRDemoFMX builds to anyone else unless it's under the GPL v3 with its source. The source itself can be shared freely, since the repository only points to FastMM5 as a submodule.
2. **Test images.** Record where each image came from, and check it may be published, before the repository's `media/` folder is shared further. `fry.jpg` was made with Immersity's AI tool, which has its own terms for what it produces.
3. **FFmpeg and the GPL.** A GPL build of FFmpeg may be given out only under the GPL, with its corresponding source offered: when MoviePlayerFMX is given to anyone with the DLLs, name the exact FFmpeg build here and link its source (and that of the GPL libraries it includes, such as x264 and x265). MoviePlayerFMX then goes under the GPL v3 too, as it already must for FastMM5 (note 1). Which build the owner's DLLs came from is not yet recorded.
