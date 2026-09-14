// libc overrides: route libm and printf/scanf-family functions to Luau builtins.
// Defining these symbols here stops the linker from pulling musl's versions, whose 64-bit integer
// arithmetic translates into very large and slow Luau code.
#include "rbx_host.h"

#include <stdarg.h>
#include <stddef.h>

extern "C" {

double sin(double x)             { return rbx_host_sin(x); }
double cos(double x)             { return rbx_host_cos(x); }
double tan(double x)             { return rbx_host_tan(x); }
double asin(double x)            { return rbx_host_asin(x); }
double acos(double x)            { return rbx_host_acos(x); }
double atan(double x)            { return rbx_host_atan(x); }
double atan2(double y, double x) { return rbx_host_atan2(y, x); }
double sinh(double x)            { return rbx_host_sinh(x); }
double cosh(double x)            { return rbx_host_cosh(x); }
double tanh(double x)            { return rbx_host_tanh(x); }
double exp(double x)             { return rbx_host_exp(x); }
double log(double x)             { return rbx_host_log(x); }
double log10(double x)           { return rbx_host_log10(x); }
double log2(double x)            { return rbx_host_log2(x); }
double pow(double x, double y)   { return rbx_host_pow(x, y); }
double fmod(double x, double y)  { return rbx_host_fmod(x, y); }
double round(double x)           { return rbx_host_round(x); }

float sinf(float x)              { return (float)rbx_host_sin(x); }
float cosf(float x)              { return (float)rbx_host_cos(x); }
float tanf(float x)              { return (float)rbx_host_tan(x); }
float asinf(float x)             { return (float)rbx_host_asin(x); }
float acosf(float x)             { return (float)rbx_host_acos(x); }
float atanf(float x)             { return (float)rbx_host_atan(x); }
float atan2f(float y, float x)   { return (float)rbx_host_atan2(y, x); }
float expf(float x)              { return (float)rbx_host_exp(x); }
float logf(float x)              { return (float)rbx_host_log(x); }
float log10f(float x)            { return (float)rbx_host_log10(x); }
float log2f(float x)             { return (float)rbx_host_log2(x); }
float powf(float x, float y)     { return (float)rbx_host_pow(x, y); }
float fmodf(float x, float y)    { return (float)rbx_host_fmod(x, y); }
float roundf(float x)            { return (float)rbx_host_round(x); }

int vsnprintf(char* buf, size_t buf_size, const char* fmt, va_list args)
{
    return rbx_host_vsnprintf(buf, (int)buf_size, fmt, args);
}

int snprintf(char* buf, size_t buf_size, const char* fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    int r = rbx_host_vsnprintf(buf, (int)buf_size, fmt, args);
    va_end(args);
    return r;
}

int vsprintf(char* buf, const char* fmt, va_list args)
{
    return rbx_host_vsnprintf(buf, 0x7FFFFFFF, fmt, args);
}

int sprintf(char* buf, const char* fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    int r = rbx_host_vsnprintf(buf, 0x7FFFFFFF, fmt, args);
    va_end(args);
    return r;
}

int vsscanf(const char* str, const char* fmt, va_list args)
{
    return rbx_host_vsscanf(str, fmt, args);
}

int sscanf(const char* str, const char* fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    int r = rbx_host_vsscanf(str, fmt, args);
    va_end(args);
    return r;
}

int vprintf(const char* fmt, va_list args)
{
    char buf[1024];
    int r = rbx_host_vsnprintf(buf, (int)sizeof(buf), fmt, args);
    rbx_host_log_message(buf);
    return r;
}

int printf(const char* fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    int r = vprintf(fmt, args);
    va_end(args);
    return r;
}

int puts(const char* str)
{
    rbx_host_log_message(str);
    return 0;
}

// Aliases defined by the same musl objects. Clang rewrites integer-only printf calls into the "small"/"i" variants,
// and any reference to them would pull musl's object in and clash with the definitions above.
int __small_vsnprintf(char* buf, size_t buf_size, const char* fmt, va_list args) { return rbx_host_vsnprintf(buf, (int)buf_size, fmt, args); }
int vsniprintf(char* buf, size_t buf_size, const char* fmt, va_list args)        { return rbx_host_vsnprintf(buf, (int)buf_size, fmt, args); }
int __small_vsprintf(char* buf, const char* fmt, va_list args)                   { return rbx_host_vsnprintf(buf, 0x7FFFFFFF, fmt, args); }
int vsiprintf(char* buf, const char* fmt, va_list args)                          { return rbx_host_vsnprintf(buf, 0x7FFFFFFF, fmt, args); }

int __small_sprintf(char* buf, const char* fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    int r = rbx_host_vsnprintf(buf, 0x7FFFFFFF, fmt, args);
    va_end(args);
    return r;
}

int siprintf(char* buf, const char* fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    int r = rbx_host_vsnprintf(buf, 0x7FFFFFFF, fmt, args);
    va_end(args);
    return r;
}

int __small_printf(const char* fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    int r = vprintf(fmt, args);
    va_end(args);
    return r;
}

int iprintf(const char* fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    int r = vprintf(fmt, args);
    va_end(args);
    return r;
}

int __isoc99_vsscanf(const char* str, const char* fmt, va_list args) { return rbx_host_vsscanf(str, fmt, args); }

int __isoc99_sscanf(const char* str, const char* fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    int r = rbx_host_vsscanf(str, fmt, args);
    va_end(args);
    return r;
}

double strtod(const char* str, char** out_end) { return rbx_host_strtod(str, out_end); }
float  strtof(const char* str, char** out_end) { return (float)rbx_host_strtod(str, out_end); }
double atof(const char* str)                   { return rbx_host_strtod(str, NULL); }

} // extern "C"

// libc++ refers to strtold: defining it here keeps the musl strtod.c object, which also defines strtod and strtof, out of the link
extern "C" long double strtold(const char* str, char** out_end)
{
    return rbx_host_strtod(str, out_end);
}
