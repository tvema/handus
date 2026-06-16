VERILATOR=verilator
IVERILOG=iverilog
VVP=vvp

FLAGS = -Wall -Winfloop -g2005-sv -DTESTMODE=1 -DTARGET_NAME="\""$(TARGET)"\""

# Target executable
TARGET = vcd_tb.vvp
WAVE_VCD = vcd_tb.vcd
WAVE_CFG = vcd_tb.gtkw

# Source files
SOURCES = ../../src/log.v vcd_tb.v

all: run

build:
	$(IVERILOG) $(FLAGS) -o $(TARGET) $(SOURCES)

run: build
	$(VVP) $(TARGET)

wave: run
	gtkwave --rcvar 'fontname_signals Monospace 11' $(WAVE_VCD) $(WAVE_CFG)

clean:
	rm -f $(TARGET) *.vcd
