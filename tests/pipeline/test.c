// Minimal pipeline test: C -> WASM (Emscripten) -> Luau (Spider) -> luau.exe
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>
#include <stdint.h>
#include <emscripten/emscripten.h>

__attribute__((import_module("env"), import_name("host_measure")))
extern double host_measure(int font, double size, int codepoint);

static int cmp_int(const void* a, const void* b) { return *(const int*)a - *(const int*)b; }

EMSCRIPTEN_KEEPALIVE int test_add(int a, int b) { return a + b; }
EMSCRIPTEN_KEEPALIVE double test_math(double x) { return sin(x) * cos(x) + pow(x, 2.5) + fmod(x, 0.7) + atan2(x, 2.0); }
EMSCRIPTEN_KEEPALIVE float test_float(float a) { return a * 1.5f + sqrtf(a); }
EMSCRIPTEN_KEEPALIVE int64_t test_i64(int64_t a, int64_t b) { return a * b + (a >> 3) - (b / 7); }
EMSCRIPTEN_KEEPALIVE char* test_alloc(int n) { char* p = (char*)malloc(n); memset(p, 'A', n - 1); p[n - 1] = 0; return p; }
EMSCRIPTEN_KEEPALIVE int test_strlen(const char* s) { return (int)strlen(s); }
EMSCRIPTEN_KEEPALIVE double test_import(int c) { return host_measure(3, 13.0, c) * 2.0; }
EMSCRIPTEN_KEEPALIVE int test_sprintf(char* buf, int n, double v) { return snprintf(buf, n, "v=%.3f %d %s %x", v, 42, "ok", 0xBEEF); }
EMSCRIPTEN_KEEPALIVE double test_sscanf(const char* s) { double d = 0; sscanf(s, "%lf", &d); return d * 2.0; }
EMSCRIPTEN_KEEPALIVE int test_qsort(void)
{
    int arr[64];
    for (int i = 0; i < 64; i++) arr[i] = (i * 7919) % 101;
    qsort(arr, 64, sizeof(int), cmp_int);
    int ok = 1;
    for (int i = 1; i < 64; i++) if (arr[i - 1] > arr[i]) ok = 0;
    return ok ? arr[63] : -1;
}
