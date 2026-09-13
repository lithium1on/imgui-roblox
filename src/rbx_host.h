// Functions implemented on the Luau side (WebAssembly imports from module "env").
// Floating point values cross the boundary as double: the Luau translation passes f64 as plain numbers.
#pragma once

#include <stdarg.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RBX_HOST_IMPORT(_NAME) __attribute__((import_module("env"), import_name(#_NAME)))

// Math (Luau's native math library is both faster and much smaller than a translated libm)
RBX_HOST_IMPORT(sin)    double rbx_host_sin(double x);
RBX_HOST_IMPORT(cos)    double rbx_host_cos(double x);
RBX_HOST_IMPORT(tan)    double rbx_host_tan(double x);
RBX_HOST_IMPORT(asin)   double rbx_host_asin(double x);
RBX_HOST_IMPORT(acos)   double rbx_host_acos(double x);
RBX_HOST_IMPORT(atan)   double rbx_host_atan(double x);
RBX_HOST_IMPORT(atan2)  double rbx_host_atan2(double y, double x);
RBX_HOST_IMPORT(sinh)   double rbx_host_sinh(double x);
RBX_HOST_IMPORT(cosh)   double rbx_host_cosh(double x);
RBX_HOST_IMPORT(tanh)   double rbx_host_tanh(double x);
RBX_HOST_IMPORT(exp)    double rbx_host_exp(double x);
RBX_HOST_IMPORT(log)    double rbx_host_log(double x);
RBX_HOST_IMPORT(log10)  double rbx_host_log10(double x);
RBX_HOST_IMPORT(log2)   double rbx_host_log2(double x);
RBX_HOST_IMPORT(pow)    double rbx_host_pow(double x, double y);
RBX_HOST_IMPORT(fmod)   double rbx_host_fmod(double x, double y);
RBX_HOST_IMPORT(round)  double rbx_host_round(double x);

// Text formatting / parsing (implemented with string.format / tonumber, reading C varargs from linear memory)
RBX_HOST_IMPORT(vsnprintf) int    rbx_host_vsnprintf(char* buf, int buf_size, const char* fmt, va_list args);
RBX_HOST_IMPORT(vsscanf)   int    rbx_host_vsscanf(const char* str, const char* fmt, va_list args);
RBX_HOST_IMPORT(strtod)    double rbx_host_strtod(const char* str, char** out_end);

// Platform
RBX_HOST_IMPORT(glyph_advance) double rbx_host_glyph_advance(int font_slot, double size, int codepoint); // < 0 when the glyph is missing
RBX_HOST_IMPORT(set_clipboard) void   rbx_host_set_clipboard(const char* text);
RBX_HOST_IMPORT(assert_failed) void   rbx_host_assert_failed(const char* expr, const char* file, int line);
RBX_HOST_IMPORT(log_message)   void   rbx_host_log_message(const char* text);

#ifdef __cplusplus
}
#endif
