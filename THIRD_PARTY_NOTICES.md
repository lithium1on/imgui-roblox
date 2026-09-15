# Third-party notices

The bundles built by this project (`imgui.luau`, `imgui_debug.luau`, `docking.luau`, `docking_debug.luau`) and its
addons (`ide.luau`) contain code from the projects below.
The project's own code is under the [MIT License](LICENSE).

## Dear ImGui

Compiled into the bundles, unmodified. <https://github.com/ocornut/imgui>: tag v1.92.9b for `imgui.luau` and
`imgui_debug.luau`, tag v1.92.9b-docking of the docking branch for `docking.luau` and `docking_debug.luau`, including
`imstb_rectpack.h` and `imstb_textedit.h` from the same repository.

```
The MIT License (MIT)

Copyright (c) 2014-2026 Omar Cornut

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## ImGuiColorTextEdit

The IDE addon (`ide.luau`, `ImGui.TextEditor`), compiled into its WebAssembly modules, unmodified. <https://github.com/goossens/ImGuiColorTextEdit>, commit f28136480fa4091164e0b528dc9cca147c5a6ee9.

```
MIT License

Copyright (c) 2024-2026 Johan A. Goossens. All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Spider

The WebAssembly-to-Luau translator. Its runtime helpers are emitted into the translated module inside the bundles and
are licensed under the [Mozilla Public License 2.0](https://mozilla.org/MPL/2.0/). Their source code is available at
<https://github.com/SovereignSatellite/Spider/tree/cfaf2fb7d68988d0183fb65d4182f3a5a1127282> (see `Targets/Luau/Printer/runtime`).

## Emscripten system libraries

Parts of the C and C++ runtime linked into the WebAssembly modules by [Emscripten](https://github.com/emscripten-core/emscripten)
6.0.9: musl libc (MIT), libc++, libc++abi and compiler-rt (Apache-2.0 WITH LLVM-exception) and dlmalloc (CC0).
See <https://github.com/emscripten-core/emscripten/blob/main/LICENSE>.

## dear_bindings

Build-time only: its metadata for Dear ImGui v1.92.9b and v1.92.9b-docking (MIT, <https://github.com/dearimgui/dear_bindings>) is used to
generate the Luau API. No dear_bindings code is included in the bundles.
