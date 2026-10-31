/* chimera_core.cpp - Supermodel as a Chimera core: the calls Chimera makes.
 *
 * The core is Supermodel's frontend. It does what upstream's SDL frontend
 * (Src/OSD/SDL/Main.cpp) does to start a game, with Chimera in the place of
 * the window, the keyboard and the sound card:
 *
 *   Init          reads the project's settings and files, finds the game in
 *                 the game list the core carries (Games.xml), loads its ROM
 *                 set from the zip, makes the OpenGL context (OSMesa, in
 *                 chimera_osd.cpp), builds the Model 3 with every board on
 *                 the one thread (MultiThreaded off) and resets it;
 *   FrameAdvance  writes the controls Chimera holds into Supermodel's inputs
 *                 (chimera_input.cpp) and runs one frame: the main board,
 *                 the graphics, the sound board, the drive board;
 *   the picture   is read back after each frame (EndFrameVideo), the sound
 *                 is the frame's samples (OutputAudio).
 *
 * Everything of the machine is in the sandbox's memory, the OpenGL's too, so
 * a savestate is the sandbox's own: nothing here saves or loads.
 */
#include "Supermodel.h"
#include "GameLoader.h"
#include "ROMSet.h"
#include "Model3/Model3.h"
#include "Inputs/Inputs.h"
#include "Graphics/Render2D.h"
#include "Graphics/New3D/New3D.h"
#include "Graphics/SuperAA.h"
#include "OSD/Audio.h"
#include "OSD/Logger.h"
#include "CPU/PowerPC/ppc.h"
#include "Util/NewConfig.h"
#include "BlockFile.h"
#include "Version.h"

#include <emulibc.h>

#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <memory>
#include <string>

#include "chimera_core.h"

extern "C" {
int chimera_setting_str(const char *key, char *out, int outsz);
long chimera_setting_long(const char *key, long dflt);
int chimera_slot_count(const char *id);
const char *chimera_slot_name(const char *id, int index, char *out, int outsz);
}

// the game list: upstream's Config/Games.xml, made a string by
// build-supermodel.sh (with this repository's test program's entry)
#include "games_xml.inc"

#define TEXT_ARG "\x1f"

namespace
{
	// The Model 3's picture: 496x384, drawn at the Drawing Scale setting's
	// multiple of it (upstream's XResolution/YResolution, its -res option).
	const unsigned kBaseWidth = 496;
	const unsigned kBaseHeight = 384;
	unsigned g_width = kBaseWidth;
	unsigned g_height = kBaseHeight;

	// The refresh rate of the hardware: 57.524160 Hz. The main board runs a
	// frame's share of that in cycles whatever this says; the sound board
	// makes 44100 / RefreshRate samples a frame (766 or 767).
	const float kRefreshHz = 57.524f;

	char g_loadError[2048];
	char g_firstError[1024];
	bool g_ready;
	CModel3 *g_model3;
	CInputs *g_inputs;
	IRender2D *g_render2D;
	IRender3D *g_render3D;
	SuperAA *g_superAA;
	Util::Config::Node *g_config;
	Game g_game;
	uint64_t g_frames;
	int64_t g_startTime;
	char g_parentName[512];

	// what Supermodel says while it starts and runs: standard error (the
	// core log), and the first error kept as the reason a start failed
	class CChimeraLogger : public CLogger
	{
	public:
		void DebugLog(const char *, va_list) override {}
		void InfoLog(const char *fmt, va_list vl) override
		{
			fputs("supermodel: ", stderr);
			vfprintf(stderr, fmt, vl);
			fputc('\n', stderr);
		}
		void ErrorLog(const char *fmt, va_list vl) override
		{
			char line[1024];
			vsnprintf(line, sizeof line, fmt, vl);
			size_t n = strlen(line);
			while (n && (line[n - 1] == '\n' || line[n - 1] == '\r'))
				line[--n] = 0;
			fprintf(stderr, "supermodel: error: %s\n", line);
			if (!g_firstError[0])
				snprintf(g_firstError, sizeof g_firstError, "%s", line);
		}
	};

	// The reason Init refused: a key of the package's language table, with
	// Supermodel's own words (or a name) as its argument.
	void fail(const char *key, const char *arg = nullptr)
	{
		const char *what = arg ? arg : (g_firstError[0] ? g_firstError : "-");
		snprintf(g_loadError, sizeof g_loadError, "%s" TEXT_ARG "%s", key, what);
		fprintf(stderr, "supermodel: Init refused: %s (%s)\n", key, what);
	}

	bool setting_bool(const char *key, bool dflt)
	{
		char buf[32];
		if (!chimera_setting_str(key, buf, sizeof buf))
			return dflt;
		return !strcmp(buf, "true") || !strcmp(buf, "1");
	}

	// What upstream's DefaultConfig() gives the emulation, with the core's
	// choices where they differ: one thread, no network, no force feedback,
	// the hardware's refresh rate, New3D.
	Util::Config::Node *make_config()
	{
		auto *config = new Util::Config::Node("Global");
		config->Set("GameXMLFile", std::string(games_xml));
		config->Set("InitStateFile", std::string(""));
		config->Set("PowerPCFrequency", 0u);
		config->Set("MultiThreaded", false);
		config->Set("GPUMultiThreaded", false);
		config->Set("IdleSkip", setting_bool("idleSkip", true));
		config->Set("ROMDirectory", std::string(""));
		config->Set("MultiTexture", false);
		config->Set("VertexShader", std::string(""));
		config->Set("FragmentShader", std::string(""));
		config->Set("EmulateSound", true);
		config->Set("Balance", 0.0f);
		config->Set("BalanceLeftRight", 0.0f);
		config->Set("BalanceFrontRear", 0.0f);
		config->Set("NbSoundChannels", 2);
		config->Set("EmulateDSB", true);
		config->Set("SoundVolume", 100);
		config->Set("MusicVolume", 100);
		config->Set("ForceFeedback", false);
		config->Set("New3DEngine", true);
		config->Set("QuadRendering", true);
		config->Set("XResolution", (int)g_width);
		config->Set("YResolution", (int)g_height);
		config->Set("FullScreen", false);
		config->Set("Supersampling", 1);
		config->Set("CRTcolors", 0);
		config->Set("UpscaleMode", 2);
		config->Set("WideScreen", false);
		config->Set("Stretch", false);
		config->Set("WideBackground", false);
		config->Set("VSync", false);
		config->Set("Throttle", false);
		config->Set("RefreshRate", kRefreshHz);
		config->Set("ShowFrameRate", false);
		config->Set("Crosshairs", 0);
		config->Set("CrosshairStyle", std::string("vector"));
		config->Set("NoWhiteFlash", false);
		config->Set("FlipStereo", false);
		config->Set("InputSystem", std::string("chimera"));
		config->Set("Network", false);
		config->Set("SimulateNet", false);
		config->Set("PortIn", 1970u);
		config->Set("PortOut", 1971u);
		config->Set("AddressOut", std::string("127.0.0.1"));
		config->Set("Outputs", std::string("none"));
		config->Set("DumpMemory", false);
		config->Set("DumpTextures", false);
		config->Set("InputDigitalSensitivity", 25u);
		config->Set("InputDigitalDecaySpeed", 50u);
		return config;
	}
}

/* ------------------------------------------------------------ for the rest of the core */

// The Model 3's real-time clock (patch 0002): the Starting Clock and the
// frames run, at the hardware's 57.524160 frames a second.
extern "C" time_t chimera_machine_time(void)
{
	return (time_t)(g_startTime + (int64_t)(g_frames * 1000000ull / 57524160ull));
}

// A clone's parent set (patch 0004): the project's "parent" file, whatever
// it is called.
extern "C" const char *chimera_parent_zip(const char *parent)
{
	(void)parent;
	return g_parentName[0] ? g_parentName : nullptr;
}

// Upstream shows a message box on an unexpected register access; the core
// writes it to its log, once per text (some come every frame while a game
// pokes), and the machine runs on as it does upstream once the box closes.
extern "C" int chimera_message_box(unsigned flags, const char *title, const char *message, void *window)
{
	(void)flags;
	(void)window;
	static char said[16][128];
	static int nsaid;
	for (int i = 0; i < nsaid; i++)
		if (!strncmp(said[i], message, sizeof said[i] - 1))
			return 0;
	if (nsaid < 16)
		snprintf(said[nsaid++], sizeof said[0], "%s", message);
	fprintf(stderr, "supermodel: %s: %s\n", title, message);
	return 0;
}

/* ------------------------------------------------------------ the calls */

ECL_EXPORT const char *GetLoadError(void) { return g_loadError; }

ECL_EXPORT int Init(void)
{
	SetLogger(std::make_shared<CChimeraLogger>());
	g_startTime = chimera_setting_long("startTime", 946684800L);

	char gameName[512];
	if (!chimera_slot_name("game", 0, gameName, sizeof gameName))
	{
		snprintf(g_loadError, sizeof g_loadError, "error.no_game");
		return 0;
	}
	if (!chimera_slot_name("parent", 0, g_parentName, sizeof g_parentName))
		g_parentName[0] = 0;

	// Drawing Scale: 1x is the Model 3's own 496x384; 2x to 4x draw the 3D at
	// that multiple (the 2D layers are scaled up), as upstream's -res does
	{
		char scale[16];
		int n = 1;
		if (chimera_setting_str("drawingScale", scale, sizeof scale))
			n = atoi(scale);
		if (n < 1 || n > 4)
			n = 1;
		g_width = kBaseWidth * (unsigned)n;
		g_height = kBaseHeight * (unsigned)n;
	}
	g_config = make_config();

	// the game: its zip, found in the game list by the CRCs of its files
	ROMSet romSet;
	{
		GameLoader loader{std::string(games_xml)};
		if (loader.Load(&g_game, &romSet, gameName))
		{
			fail("error.not_a_game");
			return 0;
		}
	}
	if (g_game.platform != Game::PLATFORM_MODEL3)
	{
		fail("error.not_model3", g_game.name.c_str());
		return 0;
	}
	fprintf(stderr, "supermodel: %s (%s), %s\n", g_game.title.c_str(), g_game.name.c_str(), g_game.version.c_str());

	// the OpenGL the renderers draw with
	if (!chimera_gl_create(g_width, g_height))
	{
		fail("error.no_opengl");
		return 0;
	}

	g_inputs = chimera_inputs_create();
	g_model3 = new CModel3(*g_config, g_inputs, nullptr, nullptr);
	if (Result::OKAY != g_model3->Init(g_game, romSet))
	{
		fail("error.init_failed");
		return 0;
	}
	romSet = ROMSet();

	// what the game remembers (its EEPROM and backup RAM), from the project's
	// save data: an NVRAM file as upstream writes it (NVRAM/<game>.nv)
	char saveName[512];
	if (chimera_slot_name("savedata", 0, saveName, sizeof saveName))
	{
		CBlockFile nvram;
		int32_t version = -1;
		if (Result::OKAY != nvram.Load(saveName) || Result::OKAY != nvram.FindBlock("Supermodel NVRAM State") ||
		    nvram.Read(&version, sizeof version) != sizeof version || version != 0)
		{
			snprintf(g_loadError, sizeof g_loadError, "error.save_not_nvram" TEXT_ARG "%s", saveName);
			fprintf(stderr, "supermodel: Init refused: %s is not a Supermodel NVRAM file\n", saveName);
			return 0;
		}
		g_model3->LoadNVRAM(&nvram);
		nvram.Close();
		fprintf(stderr, "supermodel: NVRAM from %s\n", saveName);
	}

	SetAudioType(g_game.audio);
	if (Result::OKAY != OpenAudio(*g_config))
	{
		fail("error.init_failed");
		return 0;
	}

	g_superAA = new SuperAA(1, CRTcolor::None);
	g_superAA->Init(g_width, g_height);
	g_render2D = new CRender2D(*g_config);
	g_render3D = new New3D::CNew3D(*g_config, g_game.name);
	if (Result::OKAY != g_render2D->Init(0, 0, g_width, g_height, g_width, g_height, g_superAA->GetTargetID(), UpscaleMode::Bilinear) ||
	    Result::OKAY != g_render3D->Init(0, 0, g_width, g_height, g_width, g_height, g_superAA->GetTargetID()))
	{
		fail("error.renderer_failed");
		return 0;
	}
	g_model3->AttachRenderers(g_render2D, g_render3D, g_superAA);
	chimera_inputs_attach(g_inputs, &g_game);

	g_model3->Reset();
	g_ready = true;
	return 1;
}

ECL_EXPORT void FrameAdvance(uint64_t packed)
{
	(void)packed;
	if (!g_ready)
		return;
	chimera_inputs_apply(g_inputs);
	chimera_inputs_begin_frame();
	chimera_audio_begin_frame();
	g_model3->RunFrame();
	g_frames++;
}

ECL_EXPORT void SetRenderingEnabled(int on) { chimera_set_rendering(on); }

ECL_EXPORT int GetVsyncNumerator(void) { return 57524; }
ECL_EXPORT int GetVsyncDenominator(void) { return 1000; }

// the main board's PowerPC cycles since power-on: the machine's own clock
ECL_EXPORT uint64_t GetCycleCount(void) { return chimera_ppc_cycles(); }

// the controls the game's cabinet has; the others are not shown
ECL_EXPORT int IsButtonActive(int32_t index) { return chimera_button_active(index, &g_game); }
ECL_EXPORT int IsAxisActive(int32_t index) { return chimera_axis_active(index, &g_game); }

/* ------------------------------------------------------------ memory, for the tools */

// The main board's RAM and the backup RAM, as Supermodel keeps them: in
// 32-bit words in the computer's byte order, so a 32-bit value the PowerPC
// keeps at address A is read little-endian at A, and the PowerPC's byte at
// address A is the domain's byte A ^ 3.
namespace
{
	struct Domain { const char *name; int64_t size; };
	const Domain kDomains[] = {
		{ "Main RAM", 0x800000 },
		{ "Backup RAM", 0x20000 },
	};
	const int kDomainCount = (int)(sizeof kDomains / sizeof kDomains[0]);
}

ECL_EXPORT int GetMemoryDomainCount(void) { return g_model3 ? kDomainCount : 0; }
ECL_EXPORT const char *GetMemoryDomainName(int index) { return index >= 0 && index < kDomainCount ? kDomains[index].name : nullptr; }
ECL_EXPORT int64_t GetMemoryDomainSize(int index) { return index >= 0 && index < kDomainCount ? kDomains[index].size : 0; }
ECL_EXPORT int GetMemoryDomainWritable(int index) { return index >= 0 && index < kDomainCount; }
ECL_EXPORT uint8_t *GetMemoryDomainPtr(int index)
{
	if (!g_model3)
		return nullptr;
	switch (index)
	{
	case 0: return g_model3->ChimeraRAM();
	case 1: return g_model3->ChimeraBackupRAM();
	default: return nullptr;
	}
}

/* ------------------------------------------------------------ save data */

// Emulator > Export Save Data: the game's NVRAM file, <game>.nv, as upstream
// writes it to its NVRAM folder (the EEPROM and the backup RAM), so that it
// goes back into a project, or into Supermodel, as it is. It is written into
// memory no state holds: it is the tool's answer, not the machine's.
namespace
{
	ECL_INVISIBLE uint8_t g_nvramFile[0x24000];
	ECL_INVISIBLE int64_t g_nvramSize;
	ECL_INVISIBLE char g_nvramName[64];

	void make_nvram_file(void)
	{
		g_nvramSize = 0;
		FILE *stream = fmemopen(g_nvramFile, sizeof g_nvramFile, "w+");
		if (!stream)
			return;
		CBlockFile nvram;
		if (Result::OKAY != nvram.Create(stream, "Supermodel NVRAM State", "Supermodel Version " SUPERMODEL_VERSION))
			return;
		int32_t version = 0;
		nvram.Write(&version, sizeof version);
		nvram.Write(g_game.name);
		g_model3->SaveNVRAM(&nvram);
		fflush(stream);
		g_nvramSize = ftell(stream);
		nvram.Close();
		snprintf(g_nvramName, sizeof g_nvramName, "%s.nv", g_game.name.c_str());
	}
}

ECL_EXPORT int32_t GetSaveDataFileCount(void)
{
	if (!g_ready)
		return 0;
	make_nvram_file();
	return g_nvramSize > 0 ? 1 : 0;
}
ECL_EXPORT const char *GetSaveDataFileName(int32_t index) { return index == 0 ? g_nvramName : nullptr; }
ECL_EXPORT int64_t GetSaveDataFileSize(int32_t index) { return index == 0 ? g_nvramSize : 0; }
ECL_EXPORT const uint8_t *GetSaveDataFileBuffer(int32_t index) { return index == 0 ? g_nvramFile : nullptr; }
