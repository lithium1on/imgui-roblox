#!/usr/bin/env python3
"""Dear ImGui for Roblox: set up the toolchains, build, test and benchmark, on Windows, macOS and Linux.

    python build.py setup           download Dear ImGui (master and docking), dear_bindings, Emscripten, Spider and Luau
    python build.py                 build every bundle into dist/
    python build.py docking         build some of them: imgui, imgui_debug, docking, docking_debug
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

Requirements: Python 3.9 or newer. The first setup also needs Rust (https://rustup.rs), because Spider is compiled from
source.
"""
from __future__ import annotations

import argparse
import datetime
import io
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

IMGUI_VERSION = "1.92.9b"
DEAR_BINDINGS_VERSION = "0.21"
EMSDK_VERSION = "6.0.9"
SPIDER_COMMIT = "cfaf2fb7d68988d0183fb65d4182f3a5a1127282"
LUAU_VERSION = "0.738"
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

COMMON_TESTS = [
    "api_test", "api_guide_test", "render_modes_test", "init_options_test", "input_test", "shape_detection_test",
    "measure_test", "text_metrics_test", "shutdown_test",
]
DEBUG_TESTS = ["help_section_test", "demo_stress_test"]  # need the demo window
DOCKING_TESTS = ["docking_test"]
# The line every example loads its bundle with; the test runs the example against that bundle from dist/
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
    setup_emscripten()
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


def build_variant(name: str, args) -> None:
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

    step(f"compiling to WebAssembly ({args.opt})")
    sources = [ROOT / "src" / file for file in ("imgui_rbx.cpp", "rbx_libc.cpp", "rbx_stbtt_stubs.cpp")]
    sources += [imgui / file for file in ("imgui.cpp", "imgui_draw.cpp", "imgui_widgets.cpp", "imgui_tables.cpp", "imgui_demo.cpp")]
    sources.append(gen / "imgui_bindings.cpp")
    run([
        sys.executable, em_tool("em++"), *sources,
        "-std=c++17", *args.opt.split(), "-DNDEBUG", "-fno-exceptions", "-fno-rtti",
        f"-I{imgui}", f"-I{ROOT / 'src'}", '-DIMGUI_USER_CONFIG="imconfig_roblox.h"', *cflags,
        "-sSTANDALONE_WASM", "--no-entry",
        "-sEXPORTED_FUNCTIONS=_malloc,_free,_emscripten_stack_get_current,__emscripten_stack_restore",
        "-sALLOW_MEMORY_GROWTH=1", "-sINITIAL_MEMORY=16777216", "-sSTACK_SIZE=1048576",
        "-sFILESYSTEM=0", "-sSUPPORT_LONGJMP=0",
        "-o", build / "imgui.wasm",
    ], env=emscripten_env())
    print(f"   {size(build / 'imgui.wasm')}")

    step("translating to Luau")
    with open(build / "imgui_wasm.luau", "wb") as output:
        run([spider_binary(), "compile", "-O3", build / "imgui.wasm"], stdout=output)
    print(f"   {size(build / 'imgui_wasm.luau')}")

    step("optimizing Spider's output")
    run([sys.executable, tools / "optimize_luau.py", build / "imgui_wasm.luau", build / "imgui_wasm.opt.luau"])
    wasm_luau = build / "imgui_wasm.opt.luau"
    if args.minify:
        step("minifying")
        run([sys.executable, tools / "minify_luau.py", wasm_luau, build / "imgui_wasm.min.luau"])
        wasm_luau = build / "imgui_wasm.min.luau"

    step("bundling")
    command = [
        sys.executable, tools / "bundle.py", "--wasm-luau", wasm_luau,
        "--runtime", ROOT / "luau" / "runtime.luau", "--renderer", ROOT / "luau" / "renderer.luau",
        "--bindings", gen / "bindings.luau", "--version", branch["label"], "--date", args.date,
        "--notice", NOTICE, "--out", out,
    ]
    if args.optimize_directive:
        command.append("--optimize-directive")
    run(command)


def selected_variants(names: list[str]) -> list[str]:
    names = [name for name in names if name != "all"] or list(VARIANTS)
    unknown = [name for name in names if name not in VARIANTS]
    if unknown:
        raise BuildError(f"unknown bundle {', '.join(unknown)} (expected {', '.join(VARIANTS)})")
    return names


def command_build(args) -> int:
    names = selected_variants(args.variants)
    require_compilers()
    branches = {VARIANTS[name]["branch"] for name in names}
    require([path for key in branches for path in (BRANCHES[key]["imgui"] / "imgui.cpp", BRANCHES[key]["bindings"] / "dcimgui.json")])
    started = time.time()
    for name in names:
        build_variant(name, args)
    print(f"Built in {time.time() - started:.0f} s:")
    for name in names:
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


def run_harness(script: Path, bundle: Path, tag: str, luau: str, flags: list[str]) -> tuple[int, str]:
    """Runs a tests/harness script against a bundle."""
    require_bundle(bundle)
    source = (
        read(HARNESS / "mock_env.luau") + read(HARNESS / "widgets_ui.luau")
        + "\nImGuiBundle = (function(...)\n" + read(bundle) + "\nend)()\n" + read(script)
    )
    return run_luau(script.stem + tag, source, luau, flags)


def run_example(path: Path, bundle_name: str, luau: str) -> tuple[int, str]:
    """Runs a script from examples/ against its bundle, with stand-ins for Roblox services and executor functions."""
    bundle = bundle_path(bundle_name)
    require_bundle(bundle)
    script = EXAMPLE_LOAD.sub("ImGuiBundle", read(path), count=1)
    source = (
        read(HARNESS / "mock_env.luau") + read(HARNESS / "example_env.luau")
        + "\nImGuiBundle = (function(...)\n" + read(bundle) + "\nend)()\n"
        + read(HARNESS / "example_prelude.luau") + "\ndo\n" + script + "\nend\n" + read(HARNESS / "example_driver.luau")
    )
    return run_luau(f"example_{path.stem}", source, luau, ["-O2"])


def report(label: str, test: str, code: int, output: str, started: float) -> bool:
    lines = output.splitlines()
    passed = code == 0 and any(line.startswith("RESULT 0 ") for line in lines)
    print(f"{'ok  ' if passed else 'FAIL'}  {label:<20} {test} ({time.time() - started:.1f} s)", flush=True)
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

    if not args.tests or "examples" in args.tests:
        for example in sorted(EXAMPLES.glob("*.luau")):
            started = time.time()
            match = EXAMPLE_LOAD.search(read(example))
            label = f"examples/{example.name}"
            if match is None or match.group(1) not in VARIANTS:
                print(f"FAIL  {'?':<20} {label} has no loadstring(game:HttpGet(.../releases/latest/download/<bundle>.luau))() line")
                failures += 1
                continue
            if match.group(1) not in names:
                continue
            code, output = run_example(example, match.group(1), luau)
            failures += not report(f"{match.group(1)}.luau", label, code, output, started)

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
    if not argv or argv[0] == "all" or argv[0] in VARIANTS or (argv[0].startswith("-") and argv[0] not in ("-h", "--help")):
        argv = ["build", *argv]

    parser = argparse.ArgumentParser(prog="build.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("setup", help="download and prepare every toolchain")
    build = commands.add_parser("build", help="build bundles (the default command)")
    build.add_argument("variants", nargs="*", help=f"bundles to build: {', '.join(VARIANTS)} (default: all)")
    build.add_argument("--opt", default="-O2", help="em++ optimization flags, e.g. -Oz for smaller bundles (default -O2)")
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
