#!/usr/bin/env python3
"""Dear ImGui for Roblox: set up the toolchains, build, test and benchmark, on Windows, macOS and Linux.

    python build.py setup           download Dear ImGui (master and docking), dear_bindings, the addons' libraries, Emscripten, Spider, Luau
    python build.py                 build every bundle and addon into dist/
    python build.py docking ide     build some of them (names below, without .luau)
    python build.py test            run the headless tests and the examples against every bundle
    python build.py test examples   only run the scripts in examples/ (or: test api_test --only docking)
    python build.py bench           frame time on a demo scene (--bundle, --rounds, --luau-opt)
    python build.py toolchain       compile a small C program through Emscripten, Spider and Luau
    python build.py clean           delete build/ and dist/

Bundles:
    imgui.luau           Dear ImGui (master branch) without the demo window and debug tools
    imgui_debug.luau     Dear ImGui with the demo window, metrics and debug tools
    docking.luau         Dear ImGui docking branch without the demo window and debug tools
    docking_debug.luau   docking branch with the demo window, metrics and debug tools

Addons, loaded next to any bundle with ImGui.Init({ Addons = ... }):
    ide.luau             ImGuiColorTextEdit, a code editor, as ImGui.TextEditor
    implot.luau          ImPlot, interactive plots, as ImGui.ImPlot
    imguizmo.luau        ImGuizmo, 3D move, rotate and scale handles, as ImGui.ImGuizmo
    imnodes.luau         imnodes, a node editor, as ImGui.ImNodes
    markdown.luau        imgui_markdown, Markdown text, as ImGui.Markdown
    notify.luau          ImGuiNotify, toast notifications, as ImGui.InsertNotification

Requirements: Python 3.9 or newer. The first setup also needs Rust (https://rustup.rs), because Spider is compiled from
source.
"""
from __future__ import annotations

import argparse
import datetime
import io
import json
import os
import platform
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
TOOLS = ROOT / ".tools"
THIRD_PARTY = ROOT / "third_party"
BUILD = ROOT / "build"
DIST = ROOT / "dist"
HARNESS = ROOT / "tests" / "harness"
EXAMPLES = ROOT / "examples"

sys.path.insert(0, str(ROOT / "tools"))
import wasm_info  # noqa: E402

IMGUI_VERSION = "1.92.9b"
DEAR_BINDINGS_VERSION = "0.21"
EMSDK_VERSION = "6.0.9"
SPIDER_COMMIT = "cfaf2fb7d68988d0183fb65d4182f3a5a1127282"
LUAU_VERSION = "0.738"
# Libraries the addons compile: folder in third_party/ -> (GitHub repository, commit), all made for Dear ImGui 1.92.9
LIBRARIES = {
    "ImGuiColorTextEdit": ("goossens/ImGuiColorTextEdit", "f28136480fa4091164e0b528dc9cca147c5a6ee9"),
    "implot": ("epezent/implot", "7eeb9168d2e5e6b14e266d8782ecf7e649dfc3a4"),
    "ImGuizmo": ("CedricGuillemet/ImGuizmo", "18cef5e031d8c6973d80284c67f60549fafd78c1"),
    "imnodes": ("Nelarius/imnodes", "eb36902c892548ef94f88f51ad7e7c9c7058a71c"),
    "imgui_markdown": ("enkisoftware/imgui_markdown", "4acbf80584753e15ea54eb271129995862daac8f"),
    "ImGuiNotify": ("TyomaVader/ImGuiNotify", "d00e45f8d6b1e094bc9288d20eb3d2840f6a7d73"),
}
TEXT_EDITOR = THIRD_PARTY / "ImGuiColorTextEdit"
IMPLOT = THIRD_PARTY / "implot"
IMGUIZMO = THIRD_PARTY / "ImGuizmo"
IMNODES = THIRD_PARTY / "imnodes"
IMGUI_MARKDOWN = THIRD_PARTY / "imgui_markdown"
IMGUI_NOTIFY = THIRD_PARTY / "ImGuiNotify"
ADDON_SOURCES = ROOT / "src" / "addons"
NOTICE = "Dear ImGui (c) Omar Cornut, MIT License; Spider runtime helpers, MPL-2.0"
EXE = ".exe" if os.name == "nt" else ""

BRANCHES = {
    "master": {
        "tag": f"v{IMGUI_VERSION}",
        "imgui": THIRD_PARTY / "imgui",
        "bindings": THIRD_PARTY / "dear_bindings",
        "release": f"DearBindings_v{DEAR_BINDINGS_VERSION}_ImGui_v{IMGUI_VERSION}",
        "label": IMGUI_VERSION,
    },
    "docking": {
        "tag": f"v{IMGUI_VERSION}-docking",
        "imgui": THIRD_PARTY / "imgui_docking",
        "bindings": THIRD_PARTY / "dear_bindings_docking",
        "release": f"DearBindings_v{DEAR_BINDINGS_VERSION}_ImGui_v{IMGUI_VERSION}-docking",
        "label": f"{IMGUI_VERSION} docking",
    },
}
# Without the demo window and debug tools; these bindings have no definition left to link against
LEAN_CFLAGS = ["-DIMGUI_DISABLE_DEMO_WINDOWS", "-DIMGUI_DISABLE_DEBUG_TOOLS"]
LEAN_EXCLUDE = ["ImGui_ShowFontSelector", "ImGui_DebugTextEncoding", "ImGui_DebugFlashStyleColor"]

VARIANTS = {
    "imgui": {"branch": "master", "debug": False},
    "imgui_debug": {"branch": "master", "debug": True},
    "docking": {"branch": "docking", "debug": False},
    "docking_debug": {"branch": "docking", "debug": True},
}

# An addon is C++ built into a position-independent WebAssembly side module per Dear ImGui branch, plus the Luau that
# wraps it. The runtime links the module into the running context (see "Addons" in luau/runtime.luau); every bundle
# exports the Dear ImGui symbols the addons import.
# Optional keys: "flags" (extra compiler flags), "config" (Dear ImGui user config header, default imconfig_roblox.h) and
# "enums" ((header, prefixes): C enums of the header become Luau tables, e.g. ImPlotFlags_ -> Enums.Flags).
ADDONS = {
    "ide": {
        "sources": [TEXT_EDITOR / "TextEditor.cpp", ADDON_SOURCES / "text_editor.cpp"],
        "includes": [TEXT_EDITOR],
        "luau": ROOT / "luau" / "addons" / "ide.luau",
        "notice": "ImGuiColorTextEdit (c) Johan A. Goossens, MIT License; Spider runtime helpers, MPL-2.0",
        "tests": ["text_editor_test"],
    },
    "implot": {
        "sources": [IMPLOT / "implot.cpp", IMPLOT / "implot_items.cpp", ADDON_SOURCES / "implot.cpp"],
        "includes": [IMPLOT],
        "flags": ["-DIMPLOT_CUSTOM_NUMERIC_TYPES=(double)"],  # Luau numbers are doubles: one instantiation per plot type
        "enums": (IMPLOT / "implot.h", ["ImPlot", "Im"]),
        "luau": ROOT / "luau" / "addons" / "implot.luau",
        "notice": "ImPlot (c) Evan Pezent, MIT License; Spider runtime helpers, MPL-2.0",
        "tests": ["implot_test"],
    },
    "imguizmo": {
        "sources": [IMGUIZMO / "src" / "ImGuizmo.cpp", ADDON_SOURCES / "imguizmo.cpp"],
        "includes": [IMGUIZMO / "src"],
        "luau": ROOT / "luau" / "addons" / "imguizmo.luau",
        "notice": "ImGuizmo (c) Cedric Guillemet, MIT License; Spider runtime helpers, MPL-2.0",
        "tests": ["imguizmo_test"],
    },
    "imnodes": {
        "sources": [IMNODES / "imnodes.cpp", ADDON_SOURCES / "imnodes.cpp"],
        "includes": [IMNODES, ADDON_SOURCES / "imnodes"],
        "config": "imconfig_imnodes.h",
        "enums": (IMNODES / "imnodes.h", ["ImNodes"]),
        "luau": ROOT / "luau" / "addons" / "imnodes.luau",
        "notice": "imnodes (c) Johann Muszynski, MIT License; Spider runtime helpers, MPL-2.0",
        "tests": ["imnodes_test"],
    },
    "markdown": {
        "sources": [ADDON_SOURCES / "markdown.cpp"],
        "includes": [IMGUI_MARKDOWN],
        "enums": (IMGUI_MARKDOWN / "imgui_markdown.h", ["ImGuiMarkdown"]),
        "luau": ROOT / "luau" / "addons" / "markdown.luau",
        "notice": "imgui_markdown (c) Juliette Foucaut and Doug Binks, zlib License; Spider runtime helpers, MPL-2.0",
        "tests": ["markdown_test"],
    },
    "notify": {
        "sources": [ADDON_SOURCES / "notify.cpp"],
        # The icon header stand-in comes first; toasts go in the main viewport's corner on both branches
        "includes": [ADDON_SOURCES / "notify", IMGUI_NOTIFY / "unixExample" / "backends"],
        "flags": ["-DNOTIFY_RENDER_OUTSIDE_MAIN_WINDOW=false"],
        "luau": ROOT / "luau" / "addons" / "notify.luau",
        "notice": "ImGuiNotify (c) Patrick and TyomaVader, MIT License; Spider runtime helpers, MPL-2.0",
        "tests": ["notify_test"],
    },
}
# Compiled into every addon module next to its sources
ADDON_SUPPORT = [ADDON_SOURCES / "addon_support.cpp", ROOT / "src" / "rbx_libc.cpp"]
ADDON_EXPORT = re.compile(r"RBX_EXPORT [^(]*?\b(rbx_\w+)\(")
# Emscripten libraries linked into addon modules; malloc and free come from the bundle
PIC_LIBRARIES = ["libc++-noexcept", "libc++abi-noexcept", "libc"]

COMMON_TESTS = [
    "api_test", "api_guide_test", "render_modes_test", "init_options_test", "input_test", "shape_detection_test",
    "measure_test", "text_metrics_test", "shutdown_test",
]
DEBUG_TESTS = ["help_section_test", "demo_stress_test"]  # need the demo window
DOCKING_TESTS = ["docking_test"]
# share_test runs two scripts, each with its own copy of a bundle: a second bundle with nothing new joins the first, one
# with more takes over (windows, styles, fonts and addon objects included), and bundles that each lack something the
# other has stay separate
SHARE_PAIRS = [
    ("imgui", "imgui"), ("imgui_debug", "imgui"), ("imgui", "docking_debug"), ("docking", "imgui"),
    ("docking", "imgui_debug"), ("docking_debug", "docking_debug"),
]
# The lines examples load bundles and addons with; the test runs the example against those files from dist/
EXAMPLE_LOAD = re.compile(
    r'loadstring\(game:HttpGet\("https://github\.com/lithium1on/imgui-roblox/releases/latest/download/(\w+)\.luau"\)\)\(\)'
)

COMMANDS = ("setup", "build", "test", "bench", "toolchain", "clean")


class BuildError(Exception):
    pass


def step(message: str) -> None:
    print(f"== {message}", flush=True)


def run(command, **kwargs) -> subprocess.CompletedProcess:
    command = [str(part) for part in command]
    try:
        return subprocess.run(command, check=True, **kwargs)
    except FileNotFoundError as error:
        raise BuildError(f"cannot run {command[0]}: {error}") from None
    except subprocess.CalledProcessError as error:
        raise BuildError(f"exit code {error.returncode}: {' '.join(command)}") from None


def read(path: Path) -> str:
    return Path(path).read_text(encoding="utf-8")


def relative(path: Path) -> str:
    try:
        return str(Path(path).relative_to(ROOT))
    except ValueError:
        return str(path)


def bundle_path(name: str) -> Path:
    return DIST / f"{name}.luau"


def tests_for(name: str) -> list[str]:
    variant = VARIANTS[name]
    tests = list(COMMON_TESTS)
    if variant["debug"]:
        tests += DEBUG_TESTS
    if variant["branch"] == "docking":
        tests += DOCKING_TESTS
    return tests


# ---------------------------------------------------------------------------------------------------------------- setup

def download(url: str) -> bytes:
    print(f"   downloading {url}", flush=True)
    request = urllib.request.Request(url, headers={"User-Agent": "imgui-roblox-build"})
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            return response.read()
    except OSError as error:
        raise BuildError(f"download failed: {url}: {error}") from None


def extract_archive(data: bytes, destination: Path) -> None:
    """Extracts a GitHub source archive (a single top-level folder) as `destination`."""
    if destination.exists():
        raise BuildError(f"{relative(destination)} exists but is incomplete: delete it and run setup again")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent) as temp:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            archive.extractall(temp)
        entries = list(Path(temp).iterdir())
        if len(entries) != 1 or not entries[0].is_dir():
            raise BuildError(f"unexpected archive layout for {relative(destination)}")
        shutil.move(str(entries[0]), str(destination))


def em_tool(name: str) -> Path:
    return TOOLS / "emsdk" / "upstream" / "emscripten" / f"{name}.py"


def pic_library(name: str) -> Path:
    return TOOLS / "emsdk" / "upstream" / "emscripten" / "cache" / "sysroot" / "lib" / "wasm32-emscripten" / "pic" / f"{name}.a"


def spider_binary() -> Path:
    return TOOLS / "spider" / "target" / "release" / f"spider-cli{EXE}"


def luau_binary() -> Path:
    return TOOLS / "luau" / f"luau{EXE}"


def find_cargo() -> str | None:
    found = shutil.which("cargo")
    if found:
        return found
    candidate = Path.home() / ".cargo" / "bin" / f"cargo{EXE}"
    return str(candidate) if candidate.exists() else None


def setup_imgui() -> None:
    for branch in BRANCHES.values():
        target = branch["imgui"]
        if (target / "imgui.cpp").exists():
            print(f"   Dear ImGui {branch['tag']}: {relative(target)} is ready")
            continue
        step(f"Dear ImGui {branch['tag']}")
        extract_archive(download(f"https://github.com/ocornut/imgui/archive/refs/tags/{branch['tag']}.zip"), target)


def setup_dear_bindings() -> None:
    for branch in BRANCHES.values():
        target = branch["bindings"] / "dcimgui.json"
        if target.exists():
            print(f"   dear_bindings for {branch['tag']}: {relative(target)} is ready")
            continue
        step(f"dear_bindings metadata ({branch['release']})")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(download(f"https://github.com/dearimgui/dear_bindings/releases/download/{branch['release']}/dcimgui.json"))


def setup_libraries() -> None:
    for folder, (repository, commit) in LIBRARIES.items():
        target = THIRD_PARTY / folder
        marker = target / ".commit"
        if marker.exists() and read(marker).strip() == commit:
            print(f"   {folder}: {relative(target)} is ready")
            continue
        if target.exists():
            shutil.rmtree(target)
        step(f"{folder} {commit[:8]}")
        extract_archive(download(f"https://github.com/{repository}/archive/{commit}.zip"), target)
        marker.write_text(commit + "\n", encoding="utf-8")


def setup_emscripten() -> None:
    target = TOOLS / "emsdk"
    if not (target / "emsdk.py").exists():
        step("Emscripten SDK manager")
        try:
            data = download(f"https://github.com/emscripten-core/emsdk/archive/refs/tags/{EMSDK_VERSION}.zip")
        except BuildError:
            data = download("https://github.com/emscripten-core/emsdk/archive/refs/heads/main.zip")
        extract_archive(data, target)
    if em_tool("em++").exists() and (target / ".emscripten").exists():
        print(f"   Emscripten: {relative(target)} is ready")
        return
    step(f"Emscripten {EMSDK_VERSION} (downloads the compiler, about 1 GB, the first time)")
    run([sys.executable, target / "emsdk.py", "install", EMSDK_VERSION], cwd=target)
    run([sys.executable, target / "emsdk.py", "activate", EMSDK_VERSION], cwd=target)


def setup_pic_libraries() -> None:
    missing = [name for name in PIC_LIBRARIES if not pic_library(name).exists()]
    if not missing:
        print("   Emscripten libraries for addons are ready")
        return
    step("Emscripten's C and C++ libraries for addons (position-independent, a minute)")
    run([sys.executable, em_tool("embuilder"), "build", *missing, "--pic"], env=emscripten_env())


def setup_spider() -> None:
    if spider_binary().exists():
        print(f"   Spider: {relative(spider_binary())} is ready")
        return
    source = TOOLS / "spider"
    if not (source / "Cargo.toml").exists():
        step(f"Spider {SPIDER_COMMIT[:8]} (source)")
        extract_archive(download(f"https://github.com/SovereignSatellite/Spider/archive/{SPIDER_COMMIT}.zip"), source)
    cargo = find_cargo()
    if cargo is None:
        raise BuildError(
            "Spider is compiled from source and needs Rust. Install it from https://rustup.rs, "
            "open a new terminal and run python build.py setup again."
        )
    step("compiling Spider (a few minutes the first time)")
    run([cargo, "build", "--release", "-p", "spider-cli"], cwd=source)


def setup_luau() -> None:
    if luau_binary().exists():
        print(f"   Luau: {relative(luau_binary())} is ready")
        return
    system = {"Windows": "windows", "Darwin": "macos"}.get(platform.system(), "ubuntu")
    step(f"Luau {LUAU_VERSION} (runs the tests)")
    target = TOOLS / "luau"
    target.mkdir(parents=True, exist_ok=True)
    url = f"https://github.com/luau-lang/luau/releases/download/{LUAU_VERSION}/luau-{system}.zip"
    with zipfile.ZipFile(io.BytesIO(download(url))) as archive:
        archive.extractall(target)
    for name in ("luau", "luau-analyze"):
        path = target / f"{name}{EXE}"
        if path.exists():
            path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    if not luau_binary().exists():
        raise BuildError(f"the Luau archive has no luau{EXE}")


def command_setup(args) -> int:
    setup_imgui()
    setup_dear_bindings()
    setup_libraries()
    setup_emscripten()
    setup_pic_libraries()
    setup_spider()
    setup_luau()
    print("Toolchains ready: run python build.py")
    return 0


# ---------------------------------------------------------------------------------------------------------------- build

def require(paths: list[Path]) -> None:
    missing = [relative(path) for path in paths if not path.exists()]
    if missing:
        raise BuildError(f"missing {', '.join(missing)}: run python build.py setup first")


def require_compilers() -> None:
    require([em_tool("em++"), TOOLS / "emsdk" / ".emscripten", spider_binary()])


def emscripten_env() -> dict:
    env = dict(os.environ)
    env["EM_CONFIG"] = str(TOOLS / "emsdk" / ".emscripten")
    return env


def size(path: Path) -> str:
    return f"{path.stat().st_size / 1e6:.2f} MB"


def translate(wasm: Path, out_stem: Path, args) -> Path:
    """WebAssembly -> Luau with Spider, then the optimizer and (unless --no-minify) the minifier. Returns the Luau file."""
    tools = ROOT / "tools"
    step("translating to Luau")
    raw = out_stem.with_suffix(".luau")
    with open(raw, "wb") as output:
        run([spider_binary(), "compile", "-O3", wasm], stdout=output)
    print(f"   {size(raw)}")
    step("optimizing Spider's output")
    result = out_stem.with_suffix(".opt.luau")
    run([sys.executable, tools / "optimize_luau.py", raw, result])
    if args.minify:
        step("minifying")
        minified = out_stem.with_suffix(".min.luau")
        run([sys.executable, tools / "minify_luau.py", result, minified])
        result = minified
    return result


def addon_dir(name: str, branch_key: str) -> Path:
    return BUILD / "addons" / name / branch_key


def addon_module_luau(name: str, branch_key: str, args) -> Path:
    return addon_dir(name, branch_key) / ("module.min.luau" if args.minify else "module.opt.luau")


def build_addon_module(name: str, branch_key: str, args) -> dict:
    """Builds an addon's side module for one branch (skipped when up to date). Returns its imports, exports and sizes."""
    addon = ADDONS[name]
    branch = BRANCHES[branch_key]
    work = addon_dir(name, branch_key)
    info_path = work / "module.json"
    inputs = [
        *addon["sources"], *ADDON_SUPPORT, ADDON_SOURCES / "addon_common.h", ROOT / "src" / "rbx_host.h",
        ROOT / "src" / "imconfig_roblox.h", branch["imgui"] / "imgui.h", branch["imgui"] / "imgui_internal.h", Path(__file__),
    ]
    if info_path.exists() and addon_module_luau(name, branch_key, args).exists():
        built = info_path.stat().st_mtime
        if all(path.stat().st_mtime <= built for path in inputs):
            print(f"   {name} module for the {branch_key} branch is up to date", flush=True)
            return json.loads(read(info_path))

    print(f"=== {name} addon module, {branch_key} branch", flush=True)
    setup_pic_libraries()
    work.mkdir(parents=True, exist_ok=True)
    flags = [
        "-std=c++17", "-DNDEBUG", "-fno-exceptions", "-fno-rtti", "-Oz",
        "-fPIC", "-fvisibility=hidden", "-fvisibility-inlines-hidden",
        *(f"-I{path}" for path in addon["includes"]), f"-I{branch['imgui']}", f"-I{ROOT / 'src'}", f"-I{ADDON_SOURCES}",
        f'-DIMGUI_USER_CONFIG="{addon.get("config", "imconfig_roblox.h")}"', *addon.get("flags", []),
    ]
    step("compiling (-Oz, position-independent)")
    objects = []
    for source in [*addon["sources"], *ADDON_SUPPORT]:
        obj = work / f"{source.parent.name}_{source.stem}.o"
        run([sys.executable, em_tool("em++"), "-c", source, *flags, "-o", obj], env=emscripten_env())
        objects.append(obj)
    exports = sorted({symbol for source in addon["sources"] for symbol in ADDON_EXPORT.findall(read(source))})

    step("linking the side module")
    wasm = work / "module.wasm"
    run([
        sys.executable, em_tool("em++"), *objects, "-Oz", "-sSIDE_MODULE=2", "-Wl,-Bsymbolic",
        "-sEXPORTED_FUNCTIONS=" + ",".join(f"_{symbol}" for symbol in exports),
        *(pic_library(library) for library in PIC_LIBRARIES), "-o", wasm,
    ], env=emscripten_env())
    print(f"   {size(wasm)}")
    translate(wasm, work / "module", args)

    module = wasm_info.read_module(wasm)
    info = {
        "memory_size": module["memory_size"], "memory_align": module["memory_align"], "table_size": module["table_size"],
        "imports": [list(entry) for entry in module["imports"]], "exports": [entry[0] for entry in module["exports"]],
        "signatures": {symbol: module["signatures"][symbol] for symbol in exports},
    }
    info_path.write_text(json.dumps(info, indent=1), encoding="utf-8", newline="\n")
    return info


LINKING_IMPORTS = {"memory", "__indirect_function_table", "__stack_pointer", "__memory_base", "__table_base"}


def addon_symbols(info: dict) -> list[str]:
    """Symbols an addon module expects the bundle to export: Dear ImGui functions and data, malloc, and the like."""
    own = set(info["exports"])
    wanted = set()
    for module, symbol, kind in info["imports"]:
        if module in ("GOT.mem", "GOT.func") or (module == "env" and kind == "func"):
            if symbol not in own:
                wanted.add(symbol)
    return sorted(wanted)


def runtime_host_imports() -> dict[str, set[str]]:
    """The WebAssembly imports luau/runtime.luau implements, by module."""
    imports: dict[str, set[str]] = {"env": set(), "wasi_snapshot_preview1": set()}
    for space, symbol in re.findall(r"\b(env|wasi)\.(\w+)\s*=\s*Closure", read(ROOT / "luau" / "runtime.luau")):
        imports["env" if space == "env" else "wasi_snapshot_preview1"].add(symbol)
    return imports


def check_addon_imports(name: str, info: dict, bundle_wasm: Path) -> None:
    exported = {entry[0] for entry in wasm_info.read_module(bundle_wasm)["exports"]}
    own = set(info["exports"])
    host = runtime_host_imports()
    missing = []
    for module, symbol, _ in info["imports"]:
        if (module == "env" and symbol in LINKING_IMPORTS) or symbol in exported or symbol in own:
            continue
        if symbol in host.get(module, ()):
            continue
        missing.append(f"{module}.{symbol}")
    if missing:
        raise BuildError(f"the {name} addon imports what this bundle does not provide: {', '.join(missing[:20])}")


def build_variant(name: str, args, addon_modules: dict[str, dict]) -> None:
    variant = VARIANTS[name]
    branch = BRANCHES[variant["branch"]]
    build = BUILD / name
    gen = build / "gen"
    gen.mkdir(parents=True, exist_ok=True)
    out = bundle_path(name)
    imgui = branch["imgui"]
    tools = ROOT / "tools"
    cflags = [] if variant["debug"] else LEAN_CFLAGS
    excluded = [] if variant["debug"] else LEAN_EXCLUDE
    print(f"=== {name} -> {relative(out)}", flush=True)

    step("generating bindings")
    run([
        sys.executable, tools / "gen_bindings.py", "--json", branch["bindings"] / "dcimgui.json",
        "--out-cpp", gen / "imgui_bindings.cpp", "--out-luau", gen / "bindings.luau", "--exclude", ",".join(excluded),
    ])

    # What addon modules link against: the stack pointer, a function table they can add to, memalign for their data,
    # and the symbols they import
    addon_exports = sorted({symbol for info in addon_modules.values() for symbol in addon_symbols(info)})
    step(f"compiling to WebAssembly ({args.opt})")
    sources = [ROOT / "src" / file for file in ("imgui_rbx.cpp", "rbx_libc.cpp", "rbx_stbtt_stubs.cpp")]
    sources += [imgui / file for file in ("imgui.cpp", "imgui_draw.cpp", "imgui_widgets.cpp", "imgui_tables.cpp", "imgui_demo.cpp")]
    sources.append(gen / "imgui_bindings.cpp")
    run([
        sys.executable, em_tool("em++"), *sources,
        "-std=c++17", *args.opt.split(), "-DNDEBUG", "-fno-exceptions", "-fno-rtti",
        f"-I{imgui}", f"-I{ROOT / 'src'}", '-DIMGUI_USER_CONFIG="imconfig_roblox.h"', *cflags,
        "-sSTANDALONE_WASM", "--no-entry",
        "-sEXPORTED_FUNCTIONS=_malloc,_free,_memalign,_emscripten_stack_get_current,__emscripten_stack_restore",
        "-sALLOW_MEMORY_GROWTH=1", "-sINITIAL_MEMORY=16777216", "-sSTACK_SIZE=1048576",
        "-sFILESYSTEM=0", "-sSUPPORT_LONGJMP=0",
        "-Wl,--export=__stack_pointer", "-Wl,--growable-table", *(f"-Wl,--export-if-defined={symbol}" for symbol in addon_exports),
        "-o", build / "imgui.wasm",
    ], env=emscripten_env())
    print(f"   {size(build / 'imgui.wasm')}")
    for addon_name, info in addon_modules.items():
        check_addon_imports(addon_name, info, build / "imgui.wasm")

    wasm_luau = translate(build / "imgui.wasm", build / "imgui_wasm", args)

    step("bundling")
    command = [
        sys.executable, tools / "bundle.py", "--wasm-luau", wasm_luau,
        "--runtime", ROOT / "luau" / "runtime.luau", "--renderer", ROOT / "luau" / "renderer.luau",
        "--bindings", gen / "bindings.luau", "--version", branch["label"], "--date", args.date,
        "--notice", NOTICE, "--build-name", name, "--out", out,
    ]
    if args.optimize_directive:
        command.append("--optimize-directive")
    run(command)


def extract_enums(header: Path, prefixes: list[str]) -> dict[str, dict[str, int]]:
    """The header's C enums as {table: {name: value}}: enum ImPlotFlags_ { ImPlotFlags_NoTitle = 1 << 0 } with prefix
    ImPlot becomes {"Flags": {"NoTitle": 1}}. Values may name Dear ImGui's constants (ImPlotCond_Once = ImGuiCond_Once);
    entries whose value isn't a constant expression are left out."""
    known: dict[str, int] = {}
    enum_tables(BRANCHES["master"]["imgui"] / "imgui.h", [], known)
    return enum_tables(header, prefixes, known)


def enum_tables(header: Path, prefixes: list[str], known: dict[str, int]) -> dict[str, dict[str, int]]:
    text = re.sub(r"//[^\n]*|/\*.*?\*/", "", read(header), flags=re.S)
    tables: dict[str, dict[str, int]] = {}
    for enum_name, body in re.findall(r"\benum\s+(\w+)\s*\{(.*?)\}", text, flags=re.S):
        base = enum_name.rstrip("_")
        table = next((base[len(prefix):] for prefix in prefixes if base.startswith(prefix) and len(base) > len(prefix)), base)
        entries: dict[str, int] = {}
        next_value = 0
        for item in body.split(","):
            key, _, expression = (part.strip() for part in item.partition("="))
            if not re.fullmatch(r"\w+", key):
                continue
            if expression:
                try:
                    value = int(eval(re.sub(r"\b(\d+)[uUlL]+\b", r"\1", expression), {"__builtins__": {}}, known))  # noqa: S307
                except Exception:
                    continue
            else:
                value = next_value
            known[key] = value
            next_value = value + 1
            entries[key[len(enum_name):] if key.startswith(enum_name) else key] = value
        tables[table] = entries
    return tables


def build_addon(name: str, args) -> None:
    addon = ADDONS[name]
    out = bundle_path(name)
    print(f"=== {name} -> {relative(out)}", flush=True)
    step("bundling")
    command = [
        sys.executable, ROOT / "tools" / "bundle_addon.py", "--source", addon["luau"], "--common", ROOT / "luau" / "addons" / "common.luau",
        "--version", IMGUI_VERSION, "--date", args.date, "--notice", addon["notice"], "--out", out,
    ]
    if "enums" in addon:
        enums_path = BUILD / "addons" / name / "enums.json"
        enums_path.parent.mkdir(parents=True, exist_ok=True)
        enums_path.write_text(json.dumps(extract_enums(*addon["enums"]), indent=1), encoding="utf-8", newline="\n")
        command += ["--enums", enums_path]
    for branch_key in BRANCHES:
        command += ["--module", f"{branch_key}={addon_module_luau(name, branch_key, args)},{addon_dir(name, branch_key) / 'module.json'}"]
    if args.optimize_directive:
        command.append("--optimize-directive")
    run(command)


def selected_targets(names: list[str]) -> tuple[list[str], list[str]]:
    names = [name for name in names if name != "all"] or [*VARIANTS, *ADDONS]
    unknown = [name for name in names if name not in VARIANTS and name not in ADDONS]
    if unknown:
        raise BuildError(f"unknown bundle {', '.join(unknown)} (expected {', '.join([*VARIANTS, *ADDONS])})")
    return [name for name in names if name in VARIANTS], [name for name in names if name in ADDONS]


def selected_variants(names: list[str]) -> list[str]:
    names = [name for name in names if name != "all"] or list(VARIANTS)
    unknown = [name for name in names if name not in VARIANTS]
    if unknown:
        raise BuildError(f"unknown bundle {', '.join(unknown)} (expected {', '.join(VARIANTS)})")
    return names


def command_build(args) -> int:
    variants, addons = selected_targets(args.variants)
    require_compilers()
    branches = [key for key in BRANCHES if addons or any(VARIANTS[name]["branch"] == key for name in variants)]
    require([BRANCHES[key]["imgui"] / "imgui.cpp" for key in branches])
    require([BRANCHES[VARIANTS[name]["branch"]]["bindings"] / "dcimgui.json" for name in variants])
    require([path for addon in ADDONS.values() for path in addon["sources"]])
    started = time.time()
    # Every bundle exports what the addons import, so addon modules are built first
    modules = {(addon, key): build_addon_module(addon, key, args) for addon in ADDONS for key in branches}
    for name in variants:
        build_variant(name, args, {addon: modules[(addon, VARIANTS[name]["branch"])] for addon in ADDONS})
    for name in addons:
        build_addon(name, args)
    print(f"Built in {time.time() - started:.0f} s:")
    for name in [*variants, *addons]:
        print(f"   {relative(bundle_path(name)):<24} {size(bundle_path(name))}")
    return 0


# ---------------------------------------------------------------------------------------------------------------- tests

def find_luau(explicit: str | None) -> str:
    for candidate in (explicit, os.environ.get("LUAU"), luau_binary() if luau_binary().exists() else None, shutil.which("luau")):
        if candidate:
            return str(candidate)
    raise BuildError("no Luau CLI found: run python build.py setup, or pass --luau PATH")


def run_luau(name: str, source: str, luau: str, flags: list[str]) -> tuple[int, str]:
    """Runs Luau source with the CLI; writes build/test/<name>.run.luau, .out.txt and a replay .html."""
    sys.path.insert(0, str(HARNESS))
    import make_viewer

    test_dir = BUILD / "test"
    test_dir.mkdir(parents=True, exist_ok=True)
    run_path = test_dir / f"{name}.run.luau"
    run_path.write_text(source, encoding="utf-8", newline="\n")
    try:
        process = subprocess.run([luau, *flags, str(run_path)], capture_output=True)
    except FileNotFoundError:
        raise BuildError(f"cannot run the Luau CLI at {luau}") from None
    output = (process.stdout + process.stderr).decode("utf-8", "replace").replace("\r\n", "\n")
    out_path = test_dir / f"{name}.out.txt"
    out_path.write_text(output, encoding="utf-8", newline="\n")
    make_viewer.write_viewer(out_path, test_dir / f"{name}.html")
    return process.returncode, output


def require_bundle(bundle: Path) -> None:
    if not bundle.exists():
        raise BuildError(f"{relative(bundle)} is missing: run python build.py first")


def addon_prelude(addons: list[str]) -> str:
    """Loads addons from dist/ as ImGuiAddons.<name>, as a script's loadstring would."""
    parts = ["\nImGuiAddons = {}\n"]
    for name in addons:
        require_bundle(bundle_path(name))
        parts.append(f"ImGuiAddons.{name} = (function(...)\n" + read(bundle_path(name)) + "\nend)()\n")
    return "".join(parts)


def run_harness(script: Path, bundle: Path, tag: str, luau: str, flags: list[str], addons: list[str] = ()) -> tuple[int, str]:
    """Runs a tests/harness script against a bundle (and addons)."""
    require_bundle(bundle)
    source = (
        read(HARNESS / "mock_env.luau") + read(HARNESS / "widgets_ui.luau") + addon_prelude(list(addons))
        + "\nImGuiBundle = (function(...)\n" + read(bundle) + "\nend)()\n" + read(script)
    )
    return run_luau(script.stem + tag, source, luau, flags)


def run_example(path: Path, bundle_name: str, addons: list[str], luau: str) -> tuple[int, str]:
    """Runs a script from examples/ against its bundle and addons, with stand-ins for Roblox services and executor functions."""
    bundle = bundle_path(bundle_name)
    require_bundle(bundle)
    script = EXAMPLE_LOAD.sub(lambda m: "ImGuiBundle" if m.group(1) in VARIANTS else f"ImGuiAddons.{m.group(1)}", read(path))
    source = (
        read(HARNESS / "mock_env.luau") + read(HARNESS / "example_env.luau") + addon_prelude(addons)
        + "\nImGuiBundle = (function(...)\n" + read(bundle) + "\nend)()\n"
        + read(HARNESS / "example_prelude.luau") + "\ndo\n" + script + "\nend\n" + read(HARNESS / "example_driver.luau")
    )
    return run_luau(f"example_{path.stem}", source, luau, ["-O2"])


def run_share_pair(first: str, second: str, luau: str) -> tuple[int, str]:
    """Runs tests/harness/share_test.luau with two copies of bundles, as two scripts would load them."""
    for name in (first, second):
        require_bundle(bundle_path(name))
    source = (
        read(HARNESS / "mock_env.luau") + read(HARNESS / "widgets_ui.luau") + addon_prelude(list(ADDONS))
        + f'\nShareBuildA, ShareBuildB = "{first}", "{second}"\n'
        + "ImGuiBundleA = (function(...)\n" + read(bundle_path(first)) + "\nend)()\n"
        + "ImGuiBundleB = (function(...)\n" + read(bundle_path(second)) + "\nend)()\n"
        + read(HARNESS / "share_test.luau")
    )
    return run_luau(f"share_test_{first}_{second}", source, luau, ["-O2"])


def report(label: str, test: str, code: int, output: str, started: float) -> bool:
    lines = output.splitlines()
    passed = code == 0 and any(line.startswith("RESULT 0 ") for line in lines)
    print(f"{'ok  ' if passed else 'FAIL'}  {label:<26} {test} ({time.time() - started:.1f} s)", flush=True)
    if not passed:
        shown = [line for line in lines if line.startswith("FAIL") or "error" in line.lower()] or lines[-10:]
        for line in shown[:20]:
            print(f"      {line[:200]}")
    return passed


def command_test(args) -> int:
    luau = find_luau(args.luau)
    names = selected_variants(args.only)
    failures = 0
    for name in names:
        for test in tests_for(name):
            if args.tests and test not in args.tests:
                continue
            started = time.time()
            code, output = run_harness(HARNESS / f"{test}.luau", bundle_path(name), f"_{name}", luau, ["-O2"])
            failures += not report(f"{name}.luau", test, code, output, started)
        for addon_name, addon in ADDONS.items():
            for test in addon["tests"]:
                if args.tests and test not in args.tests:
                    continue
                started = time.time()
                code, output = run_harness(HARNESS / f"{test}.luau", bundle_path(name), f"_{name}", luau, ["-O2"], [addon_name])
                failures += not report(f"{name}.luau + {addon_name}.luau", test, code, output, started)

    if not args.tests or "share_test" in args.tests:
        for first, second in SHARE_PAIRS:
            if first not in names or second not in names:
                continue
            started = time.time()
            code, output = run_share_pair(first, second, luau)
            failures += not report(f"{first}+{second}", "share_test", code, output, started)

    if not args.tests or "examples" in args.tests:
        for example in sorted(EXAMPLES.glob("*.luau")):
            started = time.time()
            loads = [match.group(1) for match in EXAMPLE_LOAD.finditer(read(example))]
            bundles = [load for load in loads if load in VARIANTS]
            label = f"examples/{example.name}"
            if len(bundles) != 1 or any(load not in VARIANTS and load not in ADDONS for load in loads):
                print(f"FAIL  {'?':<26} {label} must load one bundle (and addons) with loadstring(game:HttpGet(.../releases/latest/download/<file>.luau))()")
                failures += 1
                continue
            if bundles[0] not in names:
                continue
            addons = [load for load in loads if load in ADDONS]
            code, output = run_example(example, bundles[0], addons, luau)
            failures += not report(" + ".join(f"{load}.luau" for load in [bundles[0], *addons]), label, code, output, started)

    print(f"{failures} failure(s)")
    return 1 if failures else 0


def command_bench(args) -> int:
    luau = find_luau(args.luau)
    bundles = [Path(path).resolve() for path in args.bundle] or [bundle_path("imgui_debug")]
    for round_index in range(args.rounds):
        for index, bundle in enumerate(bundles):
            code, output = run_harness(HARNESS / "bench.luau", bundle, f"_bench{index}", luau, [args.luau_opt])
            result = next((line[len("BENCH "):] for line in output.splitlines() if line.startswith("BENCH ")), None)
            print(f"[round {round_index + 1}] {bundle.name}: {result or 'failed, see build/test'}", flush=True)
    return 0


def command_toolchain(args) -> int:
    require_compilers()
    luau = find_luau(args.luau)
    work = BUILD / "toolchain"
    work.mkdir(parents=True, exist_ok=True)
    pipeline = ROOT / "tests" / "pipeline"
    step("C -> WebAssembly (Emscripten)")
    run([
        sys.executable, em_tool("emcc"), pipeline / "test.c", "-O2", "-sSTANDALONE_WASM", "--no-entry",
        "-sEXPORTED_FUNCTIONS=_malloc,_free", "-o", work / "test.wasm",
    ], env=emscripten_env())
    step("WebAssembly -> Luau (Spider)")
    with open(work / "test.luau", "wb") as output:
        run([spider_binary(), "compile", "-O3", work / "test.wasm"], stdout=output)
    script = work / "test_run.luau"
    script.write_text(read(work / "test.luau") + read(pipeline / "footer.luau"), encoding="utf-8", newline="\n")
    step("running with Luau")
    process = subprocess.run([luau, "-O2", str(script)], capture_output=True)
    output = (process.stdout + process.stderr).decode("utf-8", "replace")
    print(output.rstrip())
    passed = process.returncode == 0 and "done: 0 failures" in output
    print("Toolchain works" if passed else "Toolchain check FAILED")
    return 0 if passed else 1


def command_clean(args) -> int:
    for path in (BUILD, DIST):
        if path.exists():
            shutil.rmtree(path)
            print(f"   removed {relative(path)}")
    return 0


# ---------------------------------------------------------------------------------------------------------------- main

def main() -> int:
    if sys.version_info < (3, 9):
        print("Python 3.9 or newer is required", file=sys.stderr)
        return 1
    argv = sys.argv[1:]
    if not argv or argv[0] == "all" or argv[0] in VARIANTS or argv[0] in ADDONS or (argv[0].startswith("-") and argv[0] not in ("-h", "--help")):
        argv = ["build", *argv]

    parser = argparse.ArgumentParser(prog="build.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("setup", help="download and prepare every toolchain")
    build = commands.add_parser("build", help="build bundles and addons (the default command)")
    build.add_argument("variants", nargs="*", help=f"what to build: {', '.join([*VARIANTS, *ADDONS])} (default: all)")
    build.add_argument("--opt", default="-O2", help="em++ optimization flags for bundles, e.g. -Oz for smaller bundles (default -O2)")
    build.add_argument("--no-minify", dest="minify", action="store_false", help="keep Spider's names and layout")
    build.add_argument("--no-optimize-directive", dest="optimize_directive", action="store_false", help="leave out --!optimize 2")
    build.add_argument("--date", default=datetime.date.today().isoformat(), help="build date written in the header")
    test = commands.add_parser("test", help="run the headless tests and the examples")
    test.add_argument("tests", nargs="*", help="only these tests, e.g. api_test, or examples for the scripts in examples/")
    test.add_argument("--only", action="append", default=[], help="only this bundle (repeatable)")
    test.add_argument("--luau", help="path to the Luau CLI")
    bench = commands.add_parser("bench", help="measure frame time")
    bench.add_argument("--bundle", action="append", default=[], help="bundle to measure (repeat to compare; default dist/imgui_debug.luau)")
    bench.add_argument("--rounds", type=int, default=2)
    bench.add_argument("--luau-opt", default="-O2", help="Luau optimization level, -O1 or -O2")
    bench.add_argument("--luau", help="path to the Luau CLI")
    toolchain = commands.add_parser("toolchain", help="check Emscripten, Spider and Luau")
    toolchain.add_argument("--luau", help="path to the Luau CLI")
    commands.add_parser("clean", help="delete build/ and dist/")
    args = parser.parse_args(argv)

    handlers = {
        "setup": command_setup, "build": command_build, "test": command_test, "bench": command_bench,
        "toolchain": command_toolchain, "clean": command_clean,
    }
    try:
        return handlers[args.command](args)
    except BuildError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())
