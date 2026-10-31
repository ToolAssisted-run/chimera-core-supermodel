/* chimera_input.cpp - Chimera's controls into Supermodel's inputs.
 *
 * Upstream reads its controls through an input system (SDL, DirectInput)
 * and a mapping per input, then polls every input once a frame. The core
 * keeps upstream's CInputs (the Model 3 reads Inputs->coin[0]->value and the
 * rest) but polls none of them: before each frame it writes into each input
 * the value its polling would have given for what Chimera holds. The table
 * of controls is tools/gen-inputs.py's (chimera_inputs.inc), in the order of
 * waterbox.config's buttons and axes.
 *
 * The 4-speed shifter keeps its gear between frames, as upstream's does: a
 * gear button pressed puts it in that gear, Shift Up and Down move it one,
 * and it starts in gear 1. That gear is the machine's state and lives in the
 * sandbox's memory like the rest.
 */
#include "Supermodel.h"
#include "Game.h"
#include "Inputs/Inputs.h"
#include "Inputs/InputSystem.h"

#include <emulibc.h>

#include <cstdint>
#include <cstring>
#include <memory>

#include "chimera_core.h"

namespace
{
	enum ButtonKind { BTN_SWITCH, BTN_GEAR, BTN_TRIGGER, BTN_OFFSCREEN };
	enum { GEAR_UP = 10, GEAR_DOWN = 11 };
	enum AxisKind { AXIS_SIGNED, AXIS_PEDAL, AXIS_PLACE };

	typedef CInput *(*InputOf)(CInputs *);

	struct ButtonDef
	{
		const char *name;
		uint32_t flags;
		ButtonKind kind;
		InputOf input;
		int arg;
	};

	struct AxisTarget
	{
		InputOf input;
		int min, rest, max;
	};

	struct AxisDef
	{
		const char *name;
		uint32_t flags;
		AxisKind kind;
		int neutral;
		AxisTarget targets[2];
	};

#include "chimera_inputs.inc"

	const int kButtonCount = (int)(sizeof kButtons / sizeof kButtons[0]);
	const int kAxisCount = (int)(sizeof kAxes / sizeof kAxes[0]);

	uint8_t g_held[kButtonCount];
	uint8_t g_wasHeld[kButtonCount];
	int32_t g_axis[kAxisCount];
	int g_gear = 1;
	bool g_inputRead;

	// An input system that has nothing: CInputs needs one, and the core
	// polls none of the inputs through it.
	class CChimeraInputSystem : public CInputSystem
	{
	public:
		CChimeraInputSystem() : CInputSystem("Chimera") {}
		bool InitializeSystem() override { return true; }
		int GetKeyIndex(const char *) override { return -1; }
		const char *GetKeyName(int) override { return nullptr; }
		bool IsKeyPressed(int, int) const override { return false; }
		int GetMouseAxisValue(int, int) const override { return 0; }
		int GetMouseWheelDir(int) const override { return 0; }
		bool IsMouseButPressed(int, int) const override { return false; }
		int GetJoyAxisValue(int, int) const override { return 0; }
		bool IsJoyPOVInDir(int, int, int) const override { return false; }
		bool IsJoyButPressed(int, int) const override { return false; }
		bool ProcessForceFeedbackCmd(int, int, ForceFeedbackCmd) override { return false; }
		int GetNumKeyboards() const override { return 0; }
		int GetNumMice() const override { return 0; }
		int GetNumJoysticks() const override { return 0; }
		const KeyDetails *GetKeyDetails(int) override { return nullptr; }
		const MouseDetails *GetMouseDetails(int) override { return nullptr; }
		const JoyDetails *GetJoyDetails(int) override { return nullptr; }
		bool Poll() override { return true; }
		void SetMouseVisibility(bool) override {}
	};

	// a value of Chimera's range on one of Supermodel's
	int scale(AxisKind kind, int32_t v, const AxisTarget &t)
	{
		switch (kind)
		{
		case AXIS_PEDAL:
			if (v < 0) v = 0;
			if (v > 32767) v = 32767;
			return t.min + (int)((int64_t)v * (t.max - t.min) / 32767);
		case AXIS_SIGNED:
			if (v < -32768) v = -32768;
			if (v > 32767) v = 32767;
			// from rest toward either end, so that 0 is exactly at rest
			if (v >= 0)
				return t.rest + (int)((int64_t)v * (t.max - t.rest) / 32767);
			return t.rest - (int)((int64_t)(-v) * (t.rest - t.min) / 32768);
		case AXIS_PLACE:
		default:
			if (v < 0) v = 0;
			if (v > 65535) v = 65535;
			return t.min + (int)((int64_t)v * (t.max - t.min) / 65535);
		}
	}
}

extern "C" void chimera_inputs_read(void) { g_inputRead = true; }

CInputs *chimera_inputs_create(void)
{
	auto system = std::shared_ptr<CInputSystem>(new CChimeraInputSystem());
	for (int a = 0; a < kAxisCount; a++)
		g_axis[a] = kAxes[a].neutral;
	return new CInputs(system);
}

void chimera_inputs_attach(CInputs *, const Game *) {}

void chimera_inputs_begin_frame(void) { g_inputRead = false; }

void chimera_inputs_apply(CInputs *in)
{
	// the gear: a gear button pressed, else a press of up or down
	for (int b = 0; b < kButtonCount; b++)
	{
		if (kButtons[b].kind != BTN_GEAR || !g_held[b] || g_wasHeld[b])
			continue;
		switch (kButtons[b].arg)
		{
		case GEAR_UP: if (g_gear < 4) g_gear++; break;
		case GEAR_DOWN: if (g_gear > 0) g_gear--; break;
		default: g_gear = kButtons[b].arg; break;
		}
	}

	for (int b = 0; b < kButtonCount; b++)
	{
		const ButtonDef &d = kButtons[b];
		const UINT16 v = g_held[b] ? 1 : 0;
		CInput *target = nullptr;
		switch (d.kind)
		{
		case BTN_SWITCH:
			target = d.input(in);
			break;
		case BTN_GEAR:
			// the up/down shifter reads the switches themselves
			if (d.arg == GEAR_UP)
				target = in->gearShiftUp.get();
			else if (d.arg == GEAR_DOWN)
				target = in->gearShiftDown.get();
			break;
		case BTN_TRIGGER:
			target = in->trigger[d.arg].get();
			in->analogTriggerLeft[d.arg]->prevValue = in->analogTriggerLeft[d.arg]->value;
			in->analogTriggerLeft[d.arg]->value = v;
			break;
		case BTN_OFFSCREEN:
			in->trigger[d.arg]->offscreenValue = v;
			break;
		}
		if (target)
		{
			target->prevValue = target->value;
			target->value = v;
		}
		g_wasHeld[b] = g_held[b];
	}
	in->gearShift4->prevValue = in->gearShift4->value;
	in->gearShift4->value = (UINT16)g_gear;

	for (int a = 0; a < kAxisCount; a++)
	{
		for (const AxisTarget &t : kAxes[a].targets)
		{
			if (!t.input)
				continue;
			CInput *target = t.input(in);
			target->prevValue = target->value;
			target->value = (UINT16)scale(kAxes[a].kind, g_axis[a], t);
		}
	}
}

int chimera_button_active(int32_t index, const Game *game)
{
	if (index < 0 || index >= kButtonCount)
		return 0;
	return (game->inputs & kButtons[index].flags) != 0;
}

int chimera_axis_active(int32_t index, const Game *game)
{
	if (index < 0 || index >= kAxisCount)
		return 0;
	return (game->inputs & kAxes[index].flags) != 0;
}

ECL_EXPORT void SetButton(int32_t index, int32_t state)
{
	if (index >= 0 && index < kButtonCount)
		g_held[index] = state != 0;
}

ECL_EXPORT void SetAxis(int32_t index, int32_t value)
{
	if (index >= 0 && index < kAxisCount)
		g_axis[index] = value;
}

ECL_EXPORT int InputWasRead(void) { return g_inputRead ? 1 : 0; }
