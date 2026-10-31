/* chimera_osd.cpp - what Supermodel asks of the computer, answered by the core.
 *
 * Upstream's Src/OSD/SDL gives Supermodel a window, an OpenGL context, a
 * sound card, threads and folders through SDL. The core gives the same calls
 * (Src/OSD/Audio.h, Video.h, Thread.h, FileSystemPath.h) from inside the
 * sandbox:
 *
 *   the OpenGL   Mesa's llvmpipe behind OSMesa, compiled into the core: a
 *                core profile 4.1 context, as upstream asks SDL for, drawing
 *                into memory the core holds;
 *   the picture  read back after each frame (EndFrameVideo), top row first;
 *                with rendering off (turbo) the frame is not drawn at all,
 *                as upstream's BeginFrameVideo can say, and the last picture
 *                stays;
 *   the sound    each frame's samples, mixed to stereo as upstream mixes
 *                for two speakers, 16-bit, 44100 Hz;
 *   threads      none: the core runs every board in turn on the one thread
 *                (MultiThreaded off), so a thread is refused, and locks,
 *                semaphores and waits do nothing;
 *   folders      none: the files are the project's, mounted by name.
 */
#include "Supermodel.h"
#include "Game.h"
#include "OSD/Audio.h"
#include "OSD/Video.h"
#include "OSD/Thread.h"
#include "OSD/FileSystemPath.h"
#include "CPU/PowerPC/ppc.h"

#include <GL/glew.h>
#include <emulibc.h>

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "chimera_core.h"

/* OSMesa's entry points, declared rather than included: <GL/osmesa.h>
 * brings Mesa's own <GL/gl.h>, which fights GLEW's. */
extern "C" {
typedef struct osmesa_context *OSMesaContext;
OSMesaContext OSMesaCreateContextAttribs(const int *attribList, OSMesaContext sharelist);
GLboolean OSMesaMakeCurrent(OSMesaContext ctx, void *buffer, GLenum type, GLsizei width, GLsizei height);
}
#define OSMESA_BGRA 0x1
#define OSMESA_FORMAT 0x22
#define OSMESA_DEPTH_BITS 0x30
#define OSMESA_STENCIL_BITS 0x31
#define OSMESA_ACCUM_BITS 0x32
#define OSMESA_PROFILE 0x33
#define OSMESA_CORE_PROFILE 0x34
#define OSMESA_CONTEXT_MAJOR_VERSION 0x36
#define OSMESA_CONTEXT_MINOR_VERSION 0x37

namespace
{
	OSMesaContext g_gl;
	uint8_t *g_surface;
	unsigned g_width, g_height;
	uint32_t *g_picture;
	bool g_render = true;

	// at most a frame of 45 Hz (upstream's MAX_SAMPLES_PER_FRAME), stereo
	const unsigned kMaxSamples = 44100 / 45 + 1;
	int16_t g_audio[kMaxSamples * 2];
	unsigned g_audioSamples;
	Game::AudioTypes g_audioType = Game::STEREO_LR;
}

/* ------------------------------------------------------------ the OpenGL and the picture */

bool chimera_gl_create(unsigned width, unsigned height)
{
	// OpenGL 4.1, core profile: what upstream asks SDL for when New3D
	// draws. The window itself has no depth or stencil buffer (New3D draws
	// into frame buffers of its own), as upstream asks.
	static const int attribs[] = {
		OSMESA_FORMAT, OSMESA_BGRA,
		OSMESA_DEPTH_BITS, 0,
		OSMESA_STENCIL_BITS, 0,
		OSMESA_ACCUM_BITS, 0,
		OSMESA_PROFILE, OSMESA_CORE_PROFILE,
		OSMESA_CONTEXT_MAJOR_VERSION, 4,
		OSMESA_CONTEXT_MINOR_VERSION, 1,
		0
	};
	g_gl = OSMesaCreateContextAttribs(attribs, nullptr);
	if (!g_gl)
	{
		ErrorLog("OSMesa refused an OpenGL 4.1 core context");
		return false;
	}
	g_width = width;
	g_height = height;
	g_surface = (uint8_t *)calloc((size_t)width * height, 4);
	g_picture = (uint32_t *)calloc((size_t)width * height, 4);
	if (!OSMesaMakeCurrent(g_gl, g_surface, GL_UNSIGNED_BYTE, (GLsizei)width, (GLsizei)height))
	{
		ErrorLog("OSMesa refused the picture's surface");
		return false;
	}
	glewExperimental = GL_TRUE;
	GLenum err = glewInit();
	if (err != GLEW_OK)
	{
		ErrorLog("OpenGL initialization failed: %s", (const char *)glewGetErrorString(err));
		return false;
	}
	glGetError(); // GLEW asks for the extensions the old way first
	fprintf(stderr, "supermodel: OpenGL %s, %s\n", (const char *)glGetString(GL_VERSION), (const char *)glGetString(GL_RENDERER));

	// what upstream's SetGLGeometry does to a new window
	glViewport(0, 0, (GLsizei)width, (GLsizei)height);
	glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
	glClear(GL_COLOR_BUFFER_BIT);
	glDisable(GL_CULL_FACE);
	const unsigned correction = (unsigned)(((height / 384.) * 2.) + 0.5); // the 2D layers' 2-pixel border
	glEnable(GL_SCISSOR_TEST);
	glScissor((GLint)correction, (GLint)correction, (GLsizei)(width - correction * 2), (GLsizei)(height - correction * 2));
	return true;
}

extern "C" void chimera_set_rendering(int on) { g_render = on != 0; }

bool BeginFrameVideo()
{
	return g_render;
}

void EndFrameVideo()
{
	if (!g_render)
		return;
	// OSMesa draws straight into the core's surface: once OpenGL has
	// finished, the picture is there, bottom row first
	glFinish();
	const uint32_t *src = (const uint32_t *)g_surface;
	for (unsigned y = 0; y < g_height; y++)
	{
		const uint32_t *in = src + (size_t)(g_height - 1 - y) * g_width;
		uint32_t *out = g_picture + (size_t)y * g_width;
		for (unsigned x = 0; x < g_width; x++)
			out[x] = in[x] | 0xFF000000u; // opaque
	}
}

ECL_EXPORT uint32_t *GetVideoBgra(void) { return g_picture; }
ECL_EXPORT int GetVideoWidth(void) { return (int)g_width; }
ECL_EXPORT int GetVideoHeight(void) { return (int)g_height; }

/* ------------------------------------------------------------ the sound */

void SetAudioCallback(AudioCallbackFPtr, void *) {}
void SetAudioEnabled(bool) {}
void SetAudioType(Game::AudioTypes type) { g_audioType = type; }
Result OpenAudio(const Util::Config::Node &) { return Result::OKAY; }
void CloseAudio() {}

void chimera_audio_begin_frame(void) { g_audioSamples = 0; }

namespace
{
	// upstream's MixINT16 (Src/OSD/SDL/Audio.cpp): the mean of the two,
	// truncated, clamped
	int16_t mix16(float x, float y)
	{
		int32_t sum = (int32_t)((x + y) * 0.5f);
		if (sum > INT16_MAX)
			sum = INT16_MAX;
		if (sum < INT16_MIN)
			sum = INT16_MIN;
		return (int16_t)sum;
	}
}

// One frame of sound from the sound board: upstream's two-speaker mix (front
// and rear of each side together), its left and right swapped for the games
// whose board has them the other way round.
bool OutputAudio(unsigned numSamples, const float *leftFront, const float *rightFront, const float *leftRear, const float *rightRear, bool flipStereo)
{
	switch (g_audioType)
	{
	case Game::STEREO_RL:
	case Game::QUAD_1_FRL_2_RRL:
	case Game::QUAD_1_RRL_2_FRL:
		flipStereo = !flipStereo;
		break;
	default:
		break;
	}
	if (numSamples > kMaxSamples - g_audioSamples)
		numSamples = kMaxSamples - g_audioSamples;
	int16_t *p = g_audio + g_audioSamples * 2;
	for (unsigned i = 0; i < numSamples; i++)
	{
		const int16_t left = mix16(leftFront[i], leftRear[i]);
		const int16_t right = mix16(rightFront[i], rightRear[i]);
		*p++ = flipStereo ? right : left;
		*p++ = flipStereo ? left : right;
	}
	g_audioSamples += numSamples;
	return false;
}

ECL_EXPORT int16_t *GetAudio(void) { return g_audio; }
ECL_EXPORT int GetAudioSampleCount(void) { return (int)g_audioSamples; }

/* ------------------------------------------------------------ the clock the core counts by */

uint64_t chimera_ppc_cycles(void) { return ppc_total_cycles(); }

/* ------------------------------------------------------------ threads: none */

CThread::CThread(const std::string &name, void *impl) : m_name(name), m_impl(impl) {}
CThread::~CThread() {}
void CThread::Sleep(UINT32) {}
// only Supermodel's timing statistics read this; they never reach the machine
UINT32 CThread::GetTicks() { return 0; }
CThread *CThread::CreateThread(const std::string &, ThreadStart, void *) { return nullptr; }
CSemaphore *CThread::CreateSemaphore(UINT32 initVal) { return new CSemaphore((void *)(uintptr_t)initVal); }
CCondVar *CThread::CreateCondVar() { return new CCondVar(nullptr); }
CMutex *CThread::CreateMutex() { return new CMutex(nullptr); }
const char *CThread::GetLastError() { return "the Chimera core runs on one thread"; }
const std::string &CThread::GetName() const { return m_name; }
UINT32 CThread::GetId() { return 0; }
int CThread::Wait() { return 0; }

CSemaphore::CSemaphore(void *impl) : m_impl(impl) {}
CSemaphore::~CSemaphore() {}
UINT32 CSemaphore::GetValue() { return (UINT32)(uintptr_t)m_impl; }
bool CSemaphore::Wait() { return true; }
bool CSemaphore::Post() { return true; }

CCondVar::CCondVar(void *impl) : m_impl(impl) {}
CCondVar::~CCondVar() {}
bool CCondVar::Wait(CMutex *) { return true; }
bool CCondVar::Signal() { return true; }
bool CCondVar::SignalAll() { return true; }

CMutex::CMutex(void *impl) : m_impl(impl) {}
CMutex::~CMutex() {}
bool CMutex::Lock() { return true; }
bool CMutex::Unlock() { return true; }

/* ------------------------------------------------------------ folders: none */

namespace FileSystemPath
{
	bool PathExists(std::string) { return false; }
	int MakeDir(std::string) { return -1; }
	std::string GetPath(PathType) { return ""; }
}
