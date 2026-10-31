/* chimera_core.h - what the core's files say to each other. */
#ifndef CHIMERA_CORE_H
#define CHIMERA_CORE_H

#include <stdint.h>

struct Game;
class CInputs;

/* chimera_osd.cpp: the OpenGL, the picture and the sound */
bool chimera_gl_create(unsigned width, unsigned height);
void chimera_audio_begin_frame(void);
uint64_t chimera_ppc_cycles(void);
extern "C" void chimera_set_rendering(int on);

/* chimera_input.cpp: Chimera's controls into Supermodel's inputs */
CInputs *chimera_inputs_create(void);
void chimera_inputs_attach(CInputs *inputs, const Game *game);
void chimera_inputs_apply(CInputs *inputs);
void chimera_inputs_begin_frame(void);
int chimera_button_active(int32_t index, const Game *game);
int chimera_axis_active(int32_t index, const Game *game);

#endif
