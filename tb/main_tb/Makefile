VERILATOR=verilator
IVERILOG=iverilog
VVP=vvp

# Target executable
TARGET = main_tb.vvp
WAVE_VCD = main_tb.vcd
WAVE_CFG = main_tb.gtkw

# Source files
SOURCES = ../../src/main.v ../../src/sync_cc.v ../../src/ascan.v ../../src/param.v ../../src/fir_filter.v ../../src/pulse.v ../../src/pulse_latch_param.v ../../src/dac_spi.v ../../src/vrc.v ../../src/vrc_param_latch.v ../../src/ascan_latch_param.v ../../src/log_latch_param.v ../../src/log.v ../../src/packet_builder.v ../../src/sys_latch_param.v ../../src/param_hub.v main_tb.v
HEADERS = ../../src/def_param.h

# Compiler flags
FLAGS = -Wall -Winfloop -g2005-sv -DTESTMODE=1 -DTARGET_NAME="\""$(TARGET)"\"" -I../../src

all: run

build: $(SOURCES) $(HEADERS)
	$(IVERILOG) $(FLAGS) -o $(TARGET) $(SOURCES)

run: build
	$(VVP) $(TARGET)

wave: run
	gtkwave --rcvar 'fontname_signals Monospace 11' $(WAVE_VCD) $(WAVE_CFG)

clean:
	rm -f $(TARGET) *.vcd