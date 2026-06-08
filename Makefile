# ==============================================================================
# Makefile для сборки и симуляции Verilog / SystemVerilog проектов
# ==============================================================================

# Имя тестбенча (цели) по умолчанию (соответствует файлу tb/main_tb.v)
TARGET ?= main_tb

# Компилятор и инструменты симуляции
IVERILOG = iverilog
VVP      = vvp
GTKWAVE  = gtkwave

# Флаги компиляции в соответствии с требованиями проекта
FLAGS = -Wall -Winfloop -g2005-sv -DTESTMODE=1 -DTARGET_NAME="\""$(TARGET)"\""

# Директории с исходным кодом и тестами
SRC_DIR = src
TB_DIR  = tb

# Поиск всех файлов исходного кода (*.v) в директориях src/ и tb/
SRCS = $(wildcard $(SRC_DIR)/*.v)
TBS  = $(wildcard $(TB_DIR)/*.v)

# Файлы симуляции
VVP_OUT  = $(TARGET).vvp
VCD_OUT  = $(TARGET).vcd
GTKW_OUT = $(TARGET).gtkw

.PHONY: all compile run wave clean help

# По умолчанию компилируем и запускаем симуляцию
all: run

# Сборка проекта (компиляция)
compile: $(VVP_OUT)

$(VVP_OUT): $(SRCS) $(TBS)
	@mkdir -p $(SRC_DIR) $(TB_DIR)
	$(IVERILOG) $(FLAGS) -o $(VVP_OUT) -s $(TARGET) $(SRCS) $(TBS)

# Запуск симуляции и генерация VCD-файла
run: compile
	$(VVP) $(VVP_OUT)

# Запуск GTKWave для просмотра диаграмм
wave: run
	@if [ -f $(VCD_OUT) ]; then \
		if [ -f $(GTKW_OUT) ]; then \
			echo "Открытие GTKWave с сохраненной конфигурацией сигналов..."; \
			$(GTKWAVE) $(VCD_OUT) $(GTKW_OUT) & \
		else \
			echo "Открытие GTKWave..."; \
			$(GTKWAVE) $(VCD_OUT) & \
		fi \
	else \
		echo "Ошибка: Файл $(VCD_OUT) не найден."; \
		echo "Убедитесь, что в вашем тестбенче $(TARGET) добавлены строки:"; \
		echo "  initial begin"; \
		echo "    \$$dumpfile(\"$(TARGET).vcd\");"; \
		echo "    \$$dumpvars(0, $(TARGET));"; \
		echo "  end"; \
	fi

# Очистка временных файлов сборки
clean:
	rm -f *.vvp *.vcd

# Справка по командам
help:
	@echo "Доступные команды:"
	@echo "  make             - Компиляция и запуск симуляции (TARGET=$(TARGET))"
	@echo "  make compile     - Только компиляция исходников"
	@echo "  make run         - Запуск скомпилированной модели и генерация VCD"
	@echo "  make wave        - Запуск симуляции и открытие результатов в GTKWave"
	@echo "  make clean       - Удаление файлов *.vvp и *.vcd"
	@echo ""
	@echo "Параметризация:"
	@echo "  Вы можете указать конкретный тестбенч для запуска:"
	@echo "  make TARGET=main_tb wave"