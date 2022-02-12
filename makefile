# project config
PROJECTNAME	:= test
STARTADDRESS:= 0x0205
LINKCONFIG	:= cerberus.cfg
SERIALPORT	:= /dev/ttyUSB0

# build config
TARGET_BIN	:= $(PROJECTNAME).bin
BUILD_DIR	:= ./build
SRC_DIRS	:= ./src
INC_DIRS	:= ./include
LIBS		:= 
CP_BINARY   := cc65
AS_BINARY	:= ca65
LNK_BINARY	:= cl65
HEXDUMP		:= xxd -c8 -g1 -o $(STARTADDRESS)
SEND_SCRIPT	:= ./tools/send.py
CPFLAGS		:= -t none -O --cpu 65c02
ASFLAGS		:=
CSRCS		:= $(shell find $(SRC_DIRS) -name '*.c')
ASRCS		:= $(shell find $(SRC_DIRS) -name '*.s')
OBJS		:= $(subst $(SRC_DIRS),$(BUILD_DIR),$(patsubst %.s,%.o,$(ASRCS)))
COBJS		:= $(subst $(SRC_DIRS),$(BUILD_DIR),$(patsubst %.c,%.o,$(CSRCS)))
# Default make target - build to binary file
# Link all objects
$(BUILD_DIR)/$(TARGET_BIN): $(OBJS) $(COBJS)
	$(LNK_BINARY) -C $(LINKCONFIG) $(OBJS) $(COBJS) $(LIBS) -vm -m $(BUILD_DIR)/$(PROJECTNAME).map -o $@

# Build step for C source - compile to assembly first
$(SRC_DIRS)/%.s: $(SRC_DIRS)/%.c
	$(CP_BINARY) $(CPFLAGS) -I $(INC_DIRS) $<
	
# Build step for assembly source - assemble each file to an object
$(BUILD_DIR)/%.o: $(SRC_DIRS)/%.s
	@mkdir -p $(BUILD_DIR)
	$(AS_BINARY) $(ASFLAGS) -l $(BUILD_DIR)/$(basename $(notdir $<)).lst $< -o $@

# Build target and upload immediately
all: $(BUILD_DIR)/$(TARGET_BIN) upload

# send to serial interface
upload: $(BUILD_DIR)/$(TARGET_BIN)
	$(SEND_SCRIPT) $(BUILD_DIR)/$(TARGET_BIN) $(SERIALPORT)

hexdump: $(BUILD_DIR)/$(TARGET_BIN)
	$(HEXDUMP) $(BUILD_DIR)/$(TARGET_BIN)
.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)
