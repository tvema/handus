VERILATOR=verilator
IVERILOG=iverilog
VVP=vvp

FLAGS = -Wall -Winfloop -g2005-sv -DTESTMODE=1

# Target executable
TARGET = vrc_tb.vvp

# Source files
SOURCES = ../../src/vrc.v ../../src/dac_spi.v vrc_tb.v

all: run

build:
	$(IVERILOG) $(FLAGS) -o $(TARGET) $(SOURCES)

run: build
	$(VVP) $(TARGET)

wave:
	gtkwave --rcvar 'fontname_signals Monospace 11' vrc_tb.vcd vrc_tb.gtkw

clean:
	rm -f $(TARGET) *.vcd
