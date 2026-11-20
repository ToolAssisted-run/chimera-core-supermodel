/* chimera_wbx.c - the project's settings and files, through the guest kit's
 * C headers (waterbox_settings.h and waterbox_slots.h read the "settings"
 * and "slots" files Chimera mounts), for the C++ of the core. */
#include <waterbox_settings.h>
#include <waterbox_slots.h>

int chimera_setting_str(const char *key, char *out, int outsz)
{
	return wbx_setting_str(key, out, outsz);
}

long chimera_setting_long(const char *key, long dflt)
{
	return wbx_setting_long(key, dflt);
}

int chimera_slot_count(const char *id)
{
	return wbx_slot_count(id);
}

const char *chimera_slot_name(const char *id, int index, char *out, int outsz)
{
	return wbx_slot_name(id, index, out, outsz);
}

/* The machine's specification, version 3 (miniBox's docs/MACHINE-SPEC.md,
 * "Virtual time"). The reason is its mmap: a bare address hint is kept only
 * where those pages are free. Under version 2 it maps there whatever lives
 * there, and LLVM's code generator inside Mesa's llvmpipe asks for the page
 * next to one it has just got by such a hint: it wiped the first page of the
 * core's picture buffer (found with the Model 1; the Model 3 and Model 2
 * only escaped because nothing lay there). The other change of version 3,
 * the machine's own clock (every clock read advances it a microsecond),
 * touches nothing here: no part of Supermodel the core runs reads a clock but
 * for statistics that never reach the machine. */
__attribute__((visibility("default"))) __attribute__((used)) const unsigned int __wbx_machine_spec = 3;
