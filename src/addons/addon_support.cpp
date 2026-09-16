// Linked into every addon's module: C library functions the runtime provides instead of WASI imports.
#include "rbx_host.h"

#include <ctime>

extern "C" {
// std::chrono, time() and ImPlot's time axes read clocks through clock_gettime: seconds from the host, so musl's
// version and its WASI clock import are never linked
int clock_gettime(clockid_t, struct timespec* ts)
{
    const double now = rbx_host_clock_now();
    ts->tv_sec = (time_t)now;
    ts->tv_nsec = (long)((now - (double)ts->tv_sec) * 1e9);
    return 0;
}

int __clock_gettime(clockid_t clock, struct timespec* ts)
{
    return clock_gettime(clock, ts);
}

// Calendar conversions in C (Emscripten's call into JavaScript). A script has no time zone: local time is UTC.
static long long DaysFromCivil(long long year, unsigned month, unsigned day)
{
    year -= month <= 2;
    const long long era = (year >= 0 ? year : year - 399) / 400;
    const unsigned year_of_era = (unsigned)(year - era * 400);
    const unsigned day_of_year = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1;
    const unsigned day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    return era * 146097 + (long long)day_of_era - 719468;
}

struct tm* gmtime_r(const time_t* timer, struct tm* out)
{
    long long days = (long long)*timer / 86400;
    long long seconds = (long long)*timer % 86400;
    if (seconds < 0)
    {
        seconds += 86400;
        days -= 1;
    }
    const long long shifted = days + 719468;
    const long long era = (shifted >= 0 ? shifted : shifted - 146096) / 146097;
    const unsigned day_of_era = (unsigned)(shifted - era * 146097);
    const unsigned year_of_era = (day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096) / 365;
    const unsigned day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    const unsigned mp = (5 * day_of_year + 2) / 153;
    const unsigned month = mp < 10 ? mp + 3 : mp - 9;
    const long long year = (long long)year_of_era + era * 400 + (month <= 2);
    out->tm_sec = (int)(seconds % 60);
    out->tm_min = (int)(seconds / 60 % 60);
    out->tm_hour = (int)(seconds / 3600);
    out->tm_mday = (int)(day_of_year - (153 * mp + 2) / 5 + 1);
    out->tm_mon = (int)month - 1;
    out->tm_year = (int)(year - 1900);
    out->tm_wday = (int)(((days + 4) % 7 + 7) % 7); // 1970-01-01 was a Thursday
    out->tm_yday = (int)(days - DaysFromCivil(year, 1, 1));
    out->tm_isdst = 0;
    return out;
}

struct tm* localtime_r(const time_t* timer, struct tm* out) { return gmtime_r(timer, out); }

time_t timegm(struct tm* value)
{
    long long year = value->tm_year + 1900LL + value->tm_mon / 12;
    int month = value->tm_mon % 12;
    if (month < 0)
    {
        month += 12;
        year -= 1;
    }
    const long long days = DaysFromCivil(year, (unsigned)month + 1, 1) + value->tm_mday - 1;
    const time_t result = (time_t)(days * 86400 + value->tm_hour * 3600LL + value->tm_min * 60LL + value->tm_sec);
    gmtime_r(&result, value);
    return result;
}

time_t mktime(struct tm* value) { return timegm(value); }

struct tm* gmtime(const time_t* timer)
{
    static struct tm result;
    return gmtime_r(timer, &result);
}

struct tm* localtime(const time_t* timer) { return gmtime(timer); }

void tzset(void) {}
}
