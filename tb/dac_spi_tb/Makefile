VERILATOR=verilator
IVERILOG=iverilog
VVP=vvp

FLAGS = -Wall -Winfloop -g2005-sv -DTESTMODE=1

# Target executable
TARGET = dac_spi_tb.vvp

# Source files
SOURCES = ../../src/dac_spi.v dac_spi_tb.v

all: run

build:
	$(IVERILOG) -o $(TARGET) $(SOURCES)

run: build
	$(VVP) $(TARGET)

wave:
	gtkwave --rcvar 'fontname_signals Monospace 11' dac_spi_tb.vcd dac_spi_tb.gtkw

clean:
	rm -f $(TARGET) *.vcd
