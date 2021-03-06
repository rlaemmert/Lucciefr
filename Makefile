#
#	Lucciefr (top-level) Makefile
#

CFLAGS ?= -Wall -Wno-comment
#CFLAGS += -Werror

include Makefile.inc

# misc
.PHONY: commit-id prepare clean mrproper docs doxygen
.PHONY: core main

# default target(s): build "main" (dynamic library)
default: main
# target for "make all"
all: clean main check

# output directories (out-of-tree build)
OBJ = obj/
LIB = lib/

#file sets
CORE_C = $(wildcard core/*.c)
CORE_O = $(addprefix $(OBJ), $(notdir $(CORE_C:.c=.o)))
CORE_LUA := $(wildcard core/*.lua)
CORE_LUA_O := $(addprefix $(OBJ), $(notdir $(CORE_LUA:.lua=.core.lua.o)))

AGENT_C = $(wildcard agent/*.c)
AGENT_O = $(addprefix $(OBJ), $(notdir $(AGENT_C:.c=.o)))

# we use a small Lua utility that "wraps" .lua scripts into binary resources
# (use @ to suppress command output, as objwrap.lua will echo a 'short' version of it)
BINWRAP=@$(LUA_DIR)/luajit$(EXE) objwrap.lua "$(OCPY) $(OFLAGS)"

# ---------------------------------------------------------------------------
# libs
# ---------------------------------------------------------------------------

# core
CORE = $(LIB)core.a
INCL += -Iinclude -Icore
$(CORE): prepare $(CORE_O)
	@$(AR) r $@ $(CORE_O)
core: $(CORE)

# LuaJIT
LUA_DIR = luajit/src
INCL += -I$(LUA_DIR)
LUA = $(LUA_DIR)/libluajit.a
$(LUA):
	@echo -e "\nBuilding LuaJIT..."
	make -j$(shell nproc) -C $(LUA_DIR) CC="$(CC) -m$(BITS)" $(TO_NULL)
luajit: $(LUA)

# MessagePack
MSGPACK := $(LIB)msgpack.a
INCL += -Imsgpack-c/include
$(MSGPACK): prepare
	@echo -e "\nBuilding msgpack-c..."
	make -C msgpack-c/ -f Makefile.lcfr LIB=../$(MSGPACK) $(TO_NULL)

# agent library target
AGENT_LIBS := $(CORE) $(CORE_LUA_O) $(MSGPACK) $(LUA)
AGENT := $(LIB)$(PREFIX_LONG)-agent-$(TARGET)$(BITS).a
INCL += -Iagent
$(AGENT): $(AGENT_O)
	@$(AR) r $@ $(AGENT_O)
agent: prepare $(AGENT)

# ---------------------------------------------------------------------------

# build rules to create $(OBJ) files from source
$(OBJ)%.o: core/%.c
	$(CC) $(CFLAGS) $(INCL) -c $< -o $@
$(OBJ)%.core.lua.o: core/%.lua $(LUA)
	$(BINWRAP) $< $@

$(OBJ)%.o: agent/%.c
	$(CC) $(CFLAGS) $(INCL) -c $< -o $@

$(OBJ)%.o: agent/$(TARGET)/%.c
	$(CC) $(CFLAGS) $(INCL) -c $< -o $@

# shared library target ("main" dll), e.g. lucciefr-win32.dll
MAIN_LIBS := $(CORE) $(CORE_LUA_O) $(MSGPACK) $(LUA)
MAIN := main/$(PREFIX_LONG)-$(TARGET)$(BITS)$(DLL)
$(MAIN): main/dllmain.c $(MAIN_LIBS)
	$(CC) $(CFLAGS) $(INCL) $(LDFLAGS) -shared -o $@ $^
main: prepare $(MAIN_LIBS) $(MAIN)

testagent: testagent.c prepare $(AGENT) $(CORE) $(CORE_LUA_O) $(MSGPACK) $(LUA)
	$(CC) $(CFLAGS) $(INCL) $(LDFLAGS) $< -o $@ $(AGENT) $(AGENT_LIBS) $(LD_LIBS)

# ---------------------------------------------------------------------------

# generate documentation
docs: doxygen

# Note that doxygen is expected (and docs/Doxyfile configured accordingly)
# to be run from the 'main' dir.
# Currently only HTML output is generated, and goes to ./html/
doxygen: docs/Doxyfile
	@echo '(Expect some warnings, which can be safely ignored.)'
	doxygen $<

# build sandbox application and run tests
check: $(CORE) $(MSGPACK) $(LUA)
	make -C tests/ INCL="$(INCL)" LIBS="$^"

# prepare build (create directories)
prepare: $(OBJ) $(LIB)
$(OBJ):
	mkdir -p $(OBJ)
$(LIB):
	mkdir -p $(LIB)

# update commit ID within include/config.h (usually a separate build step)
commit-id: include/config.h
	sed 's/#undef COMMIT_ID/#define COMMIT_ID "$(shell git describe --always --dirty)"/' -i $<

# clean up (mostly clean :D)
clean:
	rm -f $(OBJ)*
	make -C tests/ clean

# clean up (really clean!)
mrproper: clean
	rm -rf $(OBJ)
	rm -rf $(LIB)
	rm -rf main/*.so main/*.dll
	make -C msgpack-c/ -f Makefile.lcfr clean
	make -C $(LUA_DIR) clean
