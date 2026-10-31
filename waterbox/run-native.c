/* run-native.c - the native reference for the test scripts.
 *
 * Links the SAME Supermodel, core and Mesa the guest build uses, compiled
 * for this computer (build-supermodel.sh native, setup-mesa.sh -n), with the
 * sandbox's own math functions (make-native-libm.sh), and drives the core's
 * calls directly. The work dir holds what the sandbox would see mounted: the
 * game's zip, the "slots" file naming it, and the "settings" JSON.
 *
 * usage: run-native <workdir> [gate-harness options]
 */
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "gate-harness.h"

extern int Init(void);
extern const char *GetLoadError(void);
extern void SetButton(int32_t index, int32_t state);
extern void SetAxis(int32_t index, int32_t value);
extern void FrameAdvance(uint64_t packed);
extern uint32_t *GetVideoBgra(void);
extern int GetVideoWidth(void);
extern int GetVideoHeight(void);
extern int16_t *GetAudio(void);
extern int GetAudioSampleCount(void);
extern int InputWasRead(void);
extern void SetRenderingEnabled(int on);
extern int GetVsyncNumerator(void);
extern int GetVsyncDenominator(void);
extern uint64_t GetCycleCount(void);
extern int IsButtonActive(int32_t index);
extern int IsAxisActive(int32_t index);

static void frame(void) { FrameAdvance(0); }
static const uint32_t *video(int *w, int *h)
{
	*w = GetVideoWidth();
	*h = GetVideoHeight();
	return GetVideoBgra();
}
static const int16_t *audio(int *n)
{
	*n = GetAudioSampleCount();
	return GetAudio();
}

int main(int argc, char **argv)
{
	if (argc < 2)
	{
		fprintf(stderr, "usage: run-native <workdir> [options]\n");
		return 2;
	}
	static struct gate_opts o;
	if (!gate_parse_opts(argc, argv, 2, &o))
		return 2;
	/* the sandbox's environment and nothing of this computer's: Mesa and
	 * LLVM read theirs (LP_NATIVE_VECTOR_WIDTH would change llvmpipe's code) */
	/* the stall the clock test asks for is the harness's, not the machine's */
	const char *stall = getenv("GATE_STALL_US");
	char stallCopy[32] = "";
	if (stall)
		snprintf(stallCopy, sizeof stallCopy, "%s", stall);
	clearenv();
	setenv("WATERBOX", "1", 1);
	if (stallCopy[0])
		setenv("GATE_STALL_US", stallCopy, 1);
	if (chdir(argv[1]) != 0)
	{
		perror(argv[1]);
		return 1;
	}

	struct gate_core c = {
		.init = Init,
		.load_error = GetLoadError,
		.set_button = SetButton,
		.set_axis = SetAxis,
		.frame = frame,
		.video = video,
		.audio = audio,
		.input_was_read = InputWasRead,
		.vsync_numerator = GetVsyncNumerator,
		.vsync_denominator = GetVsyncDenominator,
		.pre_frame = NULL,
		.set_rendering = SetRenderingEnabled,
		.clock = GetCycleCount,
		.button_active = IsButtonActive,
		.axis_active = IsAxisActive,
	};
	return gate_run(&c, &o);
}
