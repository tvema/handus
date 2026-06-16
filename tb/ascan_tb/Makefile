VERILATOR=verilator
IVERILOG=iverilog
VVP=vvp

FLAGS = -Wall -Winfloop -g2005-sv -DTESTMODE=1 -DTARGET_NAME="\""$(TARGET)"\""

# Target executable
TARGET = ascan_tb.vvp

# Source files
SOURCES = ../../src/ascan.v ascan_tb.v

all: run

build:
	$(IVERILOG) $(FLAGS) -o $(TARGET) $(SOURCES)

run: build
	$(VVP) $(TARGET)

wave:
	gtkwave ascan_tb.vcd ascan_tb.gtkw

clean: run
	rm -f $(TARGET) *.vcd
