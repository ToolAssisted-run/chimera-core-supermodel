/* jit-symbols.c - what LLVM asks of the dynamic loader, answered by the core.
 *
 * Before LLVM's JIT makes code (llvmpipe compiles every shader with it) it
 * opens "the program itself" with dlopen(NULL), so that code it generates can
 * call functions found by name. The sandbox's C library is static and has no
 * dynamic loader: its dlopen says "Dynamic loading not supported", LLVM
 * makes no JIT, and Mesa crashes on the missing JIT. So both builds link
 * these instead of the C library's (--wrap=dlopen,dlsym,dlclose):
 *
 *   dlopen(NULL) is the program, a handle of its own; any other file is not
 *   there (the core loads no libraries);
 *   dlsym answers from the short table below and from nowhere else, in both
 *   builds alike - the native build must not find a function by name that
 *   the sandbox cannot, or the two would run different code. A name that is
 *   not in the table is said once on the console, so it can be added.
 *
 * Copied from chimera-core-godot47, where it was measured (2026-10-20) that
 * llvmpipe's code for the shaders asked for no name at all. Here, over the
 * test program's 2D layers, none was asked for either (the line below would
 * say so on the console).
 */
#include <stdio.h>
#include <string.h>

static int chimera_program;

struct jit_symbol
{
	const char *name;
	void *address;
};

static const struct jit_symbol jit_symbols[] = {
	{ "memcpy", (void *)memcpy },
	{ "memmove", (void *)memmove },
	{ "memset", (void *)memset },
};

void *__wrap_dlopen(const char *file, int mode)
{
	(void)mode;
	return file == NULL ? (void *)&chimera_program : NULL;
}

int __wrap_dlclose(void *handle)
{
	return handle == (void *)&chimera_program ? 0 : -1;
}

void *__wrap_dlsym(void *handle, const char *name)
{
	(void)handle;
	for (size_t i = 0; i < sizeof jit_symbols / sizeof jit_symbols[0]; i++)
		if (strcmp(jit_symbols[i].name, name) == 0)
			return jit_symbols[i].address;
	fprintf(stderr, "chimera: %s was asked for by name; this core gives no function by name but those in jit-symbols.c\n", name);
	return NULL;
}
