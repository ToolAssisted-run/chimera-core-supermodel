# supermodel.mk - compiles Supermodel's emulation and the core's frontend into
# one static library, for one flavour. Run by build-supermodel.sh, which sets:
#
#   SRC      the patched copy of Supermodel (build/supermodel-src)
#   OUT      the folder for this flavour's objects and library
#   GEN      the folder holding the generated 68000 core (m68kops.*)
#   WB       this repository's waterbox folder
#   KIT      the include folders of the guest kit (or the native stand-in)
#   CC CXX   the compilers, CFLAGS CXXFLAGS their flavour's flags
#
# Not built: upstream's SDL frontend (Src/OSD/SDL, the core is the frontend),
# the network (the sandbox has none), the debugger, Dear ImGui, the Pro-1000
# board (a SCSI-over-TCP board; no Model 3 game uses it), the Windows and
# macOS folders, and the Legacy3D renderer (OpenGL 2.1 with the fixed
# function pipeline and GLU; the core draws with New3D, upstream's default).

EMU_CXX := \
	Src/BlockFile.cpp Src/GameLoader.cpp Src/ROMSet.cpp \
	Src/CPU/PowerPC/ppc.cpp Src/CPU/PowerPC/PPCDisasm.cpp \
	Src/CPU/68K/68K.cpp Src/CPU/Z80/Z80.cpp \
	Src/Model3/53C810.cpp Src/Model3/93C46.cpp Src/Model3/BillBoard.cpp \
	Src/Model3/Crypto.cpp Src/Model3/DSB.cpp Src/Model3/IRQ.cpp Src/Model3/JTAG.cpp \
	Src/Model3/MPC10x.cpp Src/Model3/Model3.cpp Src/Model3/NetBoard.cpp \
	Src/Model3/NetBoardLink.cpp Src/Model3/PCI.cpp Src/Model3/RTC72421.cpp \
	Src/Model3/Real3D.cpp Src/Model3/SimNetBoard.cpp Src/Model3/SoundBoard.cpp \
	Src/Model3/TileGen.cpp \
	Src/Model3/DriveBoard/DriveBoard.cpp Src/Model3/DriveBoard/JoystickBoard.cpp \
	Src/Model3/DriveBoard/SkiBoard.cpp Src/Model3/DriveBoard/WheelBoard.cpp \
	Src/Model3/DriveBoard/Z80CTC.cpp \
	Src/Sound/SCSP.cpp Src/Sound/SCSPDSP.cpp Src/Sound/MPEG/MpegAudio.cpp \
	Src/Graphics/FBO.cpp Src/Graphics/Render2D.cpp Src/Graphics/Shader.cpp \
	Src/Graphics/SuperAA.cpp \
	Src/Graphics/New3D/GLSLShader.cpp Src/Graphics/New3D/Mat4.cpp \
	Src/Graphics/New3D/Model.cpp Src/Graphics/New3D/New3D.cpp \
	Src/Graphics/New3D/PolyHeader.cpp Src/Graphics/New3D/R3DFloat.cpp \
	Src/Graphics/New3D/R3DFrameBuffers.cpp Src/Graphics/New3D/R3DScrollFog.cpp \
	Src/Graphics/New3D/R3DShader.cpp Src/Graphics/New3D/TextureBank.cpp \
	Src/Graphics/New3D/VBO.cpp Src/Graphics/New3D/Vec.cpp \
	Src/Inputs/Input.cpp Src/Inputs/Inputs.cpp Src/Inputs/InputSource.cpp \
	Src/Inputs/InputSystem.cpp Src/Inputs/InputTypes.cpp \
	Src/Inputs/MultiInputSource.cpp \
	Src/OSD/Logger.cpp Src/OSD/Outputs.cpp \
	Src/Util/ByteSwap.cpp Src/Util/ConfigBuilders.cpp Src/Util/Format.cpp \
	Src/Util/NewConfig.cpp \
	Src/Pkgs/tinyxml2.cpp

EMU_C := Src/Pkgs/unzip.c Src/Pkgs/ioapi.c Src/Pkgs/glew.c

MUSASHI_C := m68kops.c m68kopac.c m68kopdm.c m68kopnz.c

CORE_CXX := chimera_core.cpp chimera_osd.cpp chimera_input.cpp chimera_net.cpp
CORE_C := chimera_wbx.c

INCLUDES := -I$(WB)/shim -I$(SRC)/Src -I$(SRC)/Src/OSD -I$(SRC)/Src/OSD/SDL \
	-I$(SRC)/Src/Pkgs -I$(SRC)/Src/CPU/68K/Musashi -I$(GEN) -I$(MESA)/include \
	-I$(MESA)/subprojects/zlib-1.3.1 \
	$(foreach d,$(subst :, ,$(KIT)),-I$(d))
DEFINES := -DGLEW_STATIC -DGLEW_OSMESA -DGLEW_NO_GLU -DSUPERMODEL_CHIMERA

OBJS := $(addprefix $(OUT)/emu/,$(EMU_CXX:.cpp=.o)) \
	$(addprefix $(OUT)/emu/,$(EMU_C:.c=.o)) \
	$(OUT)/emu/m68kcpu.o $(addprefix $(OUT)/emu/,$(MUSASHI_C:.c=.o)) \
	$(addprefix $(OUT)/core/,$(CORE_CXX:.cpp=.o)) \
	$(addprefix $(OUT)/core/,$(CORE_C:.c=.o))

all: $(OUT)/libsupermodel.a $(OUT)/libchimeracore.a

# the emulation and the core apart: the core's library is linked whole (only
# the sandbox calls its exports), the emulation's as a plain archive
$(OUT)/libsupermodel.a: $(filter $(OUT)/emu/%,$(OBJS))
	@rm -f $@
	ar rcs $@ $^

$(OUT)/libchimeracore.a: $(filter $(OUT)/core/%,$(OBJS))
	@rm -f $@
	ar rcs $@ $^

$(OUT)/emu/%.o: $(SRC)/%.cpp
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $(INCLUDES) $(DEFINES) -MMD -c -o $@ $<

$(OUT)/emu/%.o: $(SRC)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(INCLUDES) $(DEFINES) -MMD -c -o $@ $<

MUSASHI_FLAGS := -DINLINE="static inline" -Wno-unused-variable

$(OUT)/emu/m68kcpu.o: $(SRC)/Src/CPU/68K/Musashi/m68kcpu.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(INCLUDES) $(DEFINES) $(MUSASHI_FLAGS) -MMD -c -o $@ $<

$(OUT)/emu/m68k%.o: $(GEN)/m68k%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(INCLUDES) $(DEFINES) $(MUSASHI_FLAGS) -MMD -c -o $@ $<

$(OUT)/core/%.o: $(WB)/core/%.cpp
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $(INCLUDES) $(DEFINES) -MMD -c -o $@ $<

$(OUT)/core/%.o: $(WB)/core/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(INCLUDES) $(DEFINES) -MMD -c -o $@ $<

-include $(OBJS:.o=.d)
