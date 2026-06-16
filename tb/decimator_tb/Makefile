# Makefile для компиляции и симуляции decimator_tb

# Инструменты
SIMULATOR = iverilog
RUNNER    = vvp
VIEWER    = gtkwave

# Директории
SRC_DIR   = ../../src
TB_DIR    = .

# Список исходных файлов
# Автоматически ищет ascan.v и сопутствующие файлы дециматора в директории src
SRCS      = $(SRC_DIR)/ascan.v \
            $(wildcard $(SRC_DIR)/ascan_decimator.v) \
            $(wildcard $(SRC_DIR)/decimator.v)

TB_SRCS   = $(TB_DIR)/decimator_tb.v

# Выходные файлы компиляции и симуляции
TARGET    = decimator_tb.vvp
VCD_FILE  = decimator_tb.vcd

# Флаги компиляции
FLAGS     = -Wall -Winfloop -g2005-sv -DTESTMODE=1 -DTARGET_NAME="\""$(TARGET)"\""

# Цель по умолчанию — запуск симуляции
all: run

# Компиляция
compile: $(TARGET)

$(TARGET): $(SRCS) $(TB_SRCS)
	$(SIMULATOR) $(FLAGS) -o $(TARGET) -I$(SRC_DIR) $(TB_SRCS) $(SRCS)

# Запуск симуляции и генерация VCD-файла
run: compile
	$(RUNNER) $(TARGET)

# Открытие временных диаграмм в GTKWave
wave: run
	@if [ -f $(VCD_FILE) ]; then \
		$(VIEWER) $(VCD_FILE) & \
	else \
		echo "Ошибка: Файл $(VCD_FILE) не найден. Сначала запустите симуляцию."; \
	fi

# Очистка временных файлов сборки
clean:
	rm -f $(TARGET) $(VCD_FILE)

.PHONY: all compile run wave clean