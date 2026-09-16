// Shared by the addons' exports in src/addons: each addon is a position-independent side module built with
// -fvisibility=hidden, so only RBX_EXPORT functions stay visible to the runtime's linker.
#pragma once

#include <emscripten/emscripten.h>

#define RBX_EXPORT extern "C" EMSCRIPTEN_KEEPALIVE __attribute__((visibility("default")))
