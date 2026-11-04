// SMPC firmware: the runtime (smpc_rt.c) and the world (smpc_world.c) in one translation unit, so that the world's
// small accessors inline into the runtime's register / port / RAM functions (the MCU program, smpc_mcu_gen.c, calls
// the runtime; build.sh compiles this file instead of the two).
#include "smpc_rt.c"
#include "smpc_world.c"
