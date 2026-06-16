VERILATOR=verilator
IVERILOG=iverilog
VVP=vvp

FLAGS = -Wall -Winfloop -g2005-sv -DTESTMODE=1 -DTARGET_NAME="\""$(TARGET)"\"" -I../../src

# Target executable
TARGET = ascan_tb.vvp

# Source files
SOURCES = ../../src/ascan.v ascan_tb.v
HEADERS = ../../src/def_param.h

all: run

build:
	$(IVERILOG) $(FLAGS) -o $(TARGET) $(SOURCES)

run: build
	$(VVP) $(TARGET)

wave:
	gtkwave ascan_tb.vcd ascan_tb.gtkw

clean: run
	rm -f $(TARGET) *.vcd
