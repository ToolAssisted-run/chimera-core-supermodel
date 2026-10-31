/* GL/osmesa.h - what GLEW reads of OSMesa, for glew.c built with GLEW_OSMESA.
 *
 * Mesa's own osmesa.h brings Mesa's <GL/gl.h>, which fights GLEW's; GLEW
 * needs one function of it, the one it finds OpenGL's functions with. The
 * core's own code declares the rest it calls (chimera_osd.cpp). Found first
 * in the include path, so Mesa's header is not read by Supermodel's code.
 */
#ifndef CHIMERA_OSMESA_SHIM_H
#define CHIMERA_OSMESA_SHIM_H

#ifdef __cplusplus
extern "C" {
#endif
typedef void (*OSMESAproc)(void);
OSMESAproc OSMesaGetProcAddress(const char *funcName);
#ifdef __cplusplus
}
#endif

#endif
