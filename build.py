#!/usr/bin/env python3
"""Dear ImGui for Roblox: set up the toolchains, build, test and benchmark, on Windows, macOS and Linux.

    python build.py setup       download Dear ImGui, dear_bindings, Emscripten, Spider and Luau into third_party/ and .tools/
    python build.py             build dist/imgui_roblox.luau and dist/imgui_roblox_lite.luau
    python build.py full        build only one bundle (full or lite)
    python build.py test        run every headless test against both bundles (or: test api_test text_metrics_test)
    python build.py bench       frame time on a demo scene (--bundle, --rounds, --luau-opt)
    python build.py toolchain   compile a small C program through Emscripten, Spider and Luau
    python build.py clean       delete build/ and dist/

Requirements: Python 3.9 or newer. The first setup also needs Rust (https://rustup.rs), because Spider is compiled from
source.
"""
from __future__ import annotations

import argparse
import datetime
import io
import os
import platform
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

IMGUI_VERSION = "1.92.9b"
DEAR_BINDINGS_RELEASE = "DearBindings_v0.21_ImGui_v1.92.9b"
EMSDK_VERSION = "6.0.9"
SPIDER_COMMIT = "cfaf2fb7d68988d0183fb65d4182f3a5a1127282"
LUAU_VERSION = "0.738"
NOTICE = "Dear ImGui (c) Omar Cornut, MIT License; Spider runtime helpers, MPL-2.0"
EXE = ".exe" if os.name == "nt" else ""

VARIANTS = {
    "full": {"out": DIST / "imgui_roblox.luau", "cflags": [], "exclude": []},
    "lite": {
        "out": DIST / "imgui_roblox_lite.luau",
        "cflags": ["-DIMGUI_DISABLE_DEMO_WINDOWS", "-DIMGUI_DISABLE_DEBUG_TOOLS"],
        "exclude": ["ImGui_ShowFontSelector", "ImGui_DebugTextEncoding", "ImGui_DebugFlashStyleColor"],
    },
}
FULL_TESTS = [
    "api_test", "api_guide_test", "render_modes_test", "init_options_test", "input_test", "shape_detection_test",
    "help_section_test", "measure_test", "text_metrics_test", "demo_stress_test",
]
LITE_TESTS = [
    "api_test", "api_guide_test", "render_modes_test", "init_options_test", "input_test", "shape_detection_test",
    "measure_test", "text_metrics_test",
]
COMMANDS = ("setup", "all", "full", "lite", "test", "bench", "toolchain", "clean")


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
    target = THIRD_PARTY / "imgui"
    if (target / "imgui.cpp").exists():
        print(f"   Dear ImGui: {relative(target)} is ready")
        return
    step(f"Dear ImGui v{IMGUI_VERSION}")
    extract_archive(download(f"https://github.com/ocornut/imgui/archive/refs/tags/v{IMGUI_VERSION}.zip"), target)


def setup_dear_bindings() -> None:
    target = THIRD_PARTY / "dear_bindings" / "dcimgui.json"
    if target.exists():
        print(f"   dear_bindings: {relative(target)} is ready")
        return
    step(f"dear_bindings metadata ({DEAR_BINDINGS_RELEASE})")
    target.parent.mkdir(parents=True, exist_ok=True)
    url = f"https://github.com/dearimgui/dear_bindings/releases/download/{DEAR_BINDINGS_RELEASE}/dcimgui.json"
    target.write_bytes(download(url))


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

def require_toolchain() -> None:
    required = [
        em_tool("em++"), TOOLS / "emsdk" / ".emscripten", spider_binary(),
        THIRD_PARTY / "imgui" / "imgui.cpp", THIRD_PARTY / "dear_bindings" / "dcimgui.json",
    ]
    missing = [relative(path) for path in required if not path.exists()]
    if missing:
        raise BuildError(f"missing {', '.join(missing)}: run python build.py setup first")


def emscripten_env() -> dict:
    env = dict(os.environ)
    env["EM_CONFIG"] = str(TOOLS / "emsdk" / ".emscripten")
    return env


def size(path: Path) -> str:
    return f"{path.stat().st_size / 1e6:.2f} MB"


def build_variant(name: str, args) -> None:
    variant = VARIANTS[name]
    build = BUILD / name
    gen = build / "gen"
    gen.mkdir(parents=True, exist_ok=True)
    out = variant["out"]
    imgui = THIRD_PARTY / "imgui"
    tools = ROOT / "tools"
    print(f"=== {name} -> {relative(out)}", flush=True)

    step("generating bindings")
    run([
        sys.executable, tools / "gen_bindings.py", "--json", THIRD_PARTY / "dear_bindings" / "dcimgui.json",
        "--out-cpp", gen / "imgui_bindings.cpp", "--out-luau", gen / "bindings.luau",
        "--exclude", ",".join(variant["exclude"]),
    ])

    step(f"compiling to WebAssembly ({args.opt})")
    sources = [ROOT / "src" / name for name in ("imgui_rbx.cpp", "rbx_libc.cpp", "rbx_stbtt_stubs.cpp")]
    sources += [imgui / name for name in ("imgui.cpp", "imgui_draw.cpp", "imgui_widgets.cpp", "imgui_tables.cpp", "imgui_demo.cpp")]
    sources.append(gen / "imgui_bindings.cpp")
    run([
        sys.executable, em_tool("em++"), *sources,
        "-std=c++17", *args.opt.split(), "-DNDEBUG", "-fno-exceptions", "-fno-rtti",
        f"-I{imgui}", f"-I{ROOT / 'src'}", '-DIMGUI_USER_CONFIG="imconfig_roblox.h"', *variant["cflags"],
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
        "--bindings", gen / "bindings.luau", "--version", IMGUI_VERSION, "--date", args.date,
        "--notice", NOTICE, "--out", out,
    ]
    if args.optimize_directive:
        command.append("--optimize-directive")
    run(command)


def command_build(args) -> int:
    require_toolchain()
    started = time.time()
    names = ["full", "lite"] if args.command == "all" else [args.command]
    for name in names:
        build_variant(name, args)
    print(f"Built in {time.time() - started:.0f} s:")
    for name in names:
        print(f"   {relative(VARIANTS[name]['out'])}  {size(VARIANTS[name]['out'])}")
    return 0


# ---------------------------------------------------------------------------------------------------------------- tests

def find_luau(explicit: str | None) -> str:
    for candidate in (explicit, os.environ.get("LUAU"), luau_binary() if luau_binary().exists() else None, shutil.which("luau")):
        if candidate:
            return str(candidate)
    raise BuildError("no Luau CLI found: run python build.py setup, or pass --luau PATH")


def run_harness(script: Path, bundle: Path, tag: str, luau: str, flags: list[str]) -> tuple[int, str]:
    """Runs a harness script against a bundle; writes build/test/<name>.run.luau, .out.txt and .html."""
    sys.path.insert(0, str(HARNESS))
    import make_viewer

    if not bundle.exists():
        raise BuildError(f"{relative(bundle)} is missing: run python build.py first")
    test_dir = BUILD / "test"
    test_dir.mkdir(parents=True, exist_ok=True)
    name = script.stem + tag
    source = (
        read(HARNESS / "mock_env.luau") + read(HARNESS / "widgets_ui.luau")
        + "\nImGuiBundle = (function(...)\n" + read(bundle) + "\nend)()\n" + read(script)
    )
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


def command_test(args) -> int:
    luau = find_luau(args.luau)
    suites = [(VARIANTS["full"]["out"], "", FULL_TESTS), (VARIANTS["lite"]["out"], "_lite", LITE_TESTS)]
    failures = 0
    for bundle, tag, tests in suites:
        for test in tests:
            if args.tests and test not in args.tests:
                continue
            started = time.time()
            code, output = run_harness(HARNESS / f"{test}.luau", bundle, tag, luau, ["-O2"])
            lines = output.splitlines()
            passed = code == 0 and any(line.startswith("RESULT 0 ") for line in lines)
            print(f"{'ok  ' if passed else 'FAIL'}  {bundle.name:<24} {test} ({time.time() - started:.1f} s)", flush=True)
            if not passed:
                failures += 1
                shown = [line for line in lines if line.startswith("FAIL") or "error" in line.lower()] or lines[-10:]
                for line in shown[:20]:
                    print(f"      {line[:200]}")
    print(f"{failures} failure(s)")
    return 1 if failures else 0


def command_bench(args) -> int:
    luau = find_luau(args.luau)
    bundles = [Path(path).resolve() for path in args.bundle] or [VARIANTS["full"]["out"]]
    for round_index in range(args.rounds):
        for index, bundle in enumerate(bundles):
            code, output = run_harness(HARNESS / "bench.luau", bundle, f"_bench{index}", luau, [args.luau_opt])
            result = next((line[len("BENCH "):] for line in output.splitlines() if line.startswith("BENCH ")), None)
            print(f"[round {round_index + 1}] {bundle.name}: {result or 'failed, see build/test'}", flush=True)
    return 0


def command_toolchain(args) -> int:
    require_toolchain()
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
    if not argv or (argv[0] not in COMMANDS and argv[0] not in ("-h", "--help")):
        argv = ["all", *argv]

    parser = argparse.ArgumentParser(prog="build.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("setup", help="download and prepare every toolchain")
    for name, text in (("all", "build both bundles"), ("full", "build dist/imgui_roblox.luau"), ("lite", "build dist/imgui_roblox_lite.luau")):
        sub = commands.add_parser(name, help=text)
        sub.add_argument("--opt", default="-O2", help="em++ optimization flags, e.g. -Oz for a smaller bundle (default -O2)")
        sub.add_argument("--no-minify", dest="minify", action="store_false", help="keep Spider's names and layout")
        sub.add_argument("--no-optimize-directive", dest="optimize_directive", action="store_false", help="leave out --!optimize 2")
        sub.add_argument("--date", default=datetime.date.today().isoformat(), help="build date written in the header")
    test = commands.add_parser("test", help="run the headless tests")
    test.add_argument("tests", nargs="*", help="only these tests, e.g. api_test")
    test.add_argument("--luau", help="path to the Luau CLI")
    bench = commands.add_parser("bench", help="measure frame time")
    bench.add_argument("--bundle", action="append", default=[], help="bundle to measure (repeat to compare)")
    bench.add_argument("--rounds", type=int, default=2)
    bench.add_argument("--luau-opt", default="-O2", help="Luau optimization level, -O1 or -O2")
    bench.add_argument("--luau", help="path to the Luau CLI")
    toolchain = commands.add_parser("toolchain", help="check Emscripten, Spider and Luau")
    toolchain.add_argument("--luau", help="path to the Luau CLI")
    commands.add_parser("clean", help="delete build/ and dist/")
    args = parser.parse_args(argv)

    handlers = {
        "setup": command_setup, "all": command_build, "full": command_build, "lite": command_build,
        "test": command_test, "bench": command_bench, "toolchain": command_toolchain, "clean": command_clean,
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
