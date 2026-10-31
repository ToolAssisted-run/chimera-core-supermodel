/* SDLIncludes.h - the core's stand-in for Supermodel's SDL header.
 *
 * Supermodel's emulation includes SDL for one thing only: a message box it
 * shows on an unexpected register access of the net board or the Model 3's
 * system registers. The core has no window; the message goes to the core's
 * log (standard error), once per text, and the machine runs on as upstream's
 * does after the box is closed. Found first in the include path, so
 * upstream's own SDLIncludes.h (Src/OSD/SDL) is never read.
 */
#ifndef INCLUDED_SDLINCLUDES_H
#define INCLUDED_SDLINCLUDES_H

#define SDL_MESSAGEBOX_ERROR 0x10

#ifdef __cplusplus
extern "C" {
#endif
int chimera_message_box(unsigned flags, const char *title, const char *message, void *window);
#ifdef __cplusplus
}
#endif

#define SDL_ShowSimpleMessageBox(flags, title, message, window) chimera_message_box((flags), (title), (message), (window))

#endif
