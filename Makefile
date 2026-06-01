# Simulation for tokyo_mac RTL and testbenches (Icarus Verilog)
IVERILOG ?= iverilog
VVP      ?= vvp
IVFLAGS  ?= -g2012 -Wall

RTL      := rtl/mac_pe.sv rtl/systolic_array.sv rtl/uart.sv rtl/uart_host_if.sv rtl/tokyo_mac_top.sv
TB_PKG   := tb/systolic_ref_model.sv
TB_PE    := tb/mac_pe_tb.sv
TB_ARRAY := tb/systolic_array_tb.sv tb/systolic_array_top.sv

BUILD_DIR := build
VVP_PE    := $(BUILD_DIR)/mac_pe_tb.vvp
VVP_ARRAY := $(BUILD_DIR)/systolic_array_tb_N%0d.vvp

VVP_UART := $(BUILD_DIR)/uart_tb.vvp
TB_UART  := tb/uart_tb.sv
VVP_TOP  := $(BUILD_DIR)/tokyo_mac_top_tb.vvp
TB_TOP   := tb/tokyo_mac_top_tb.sv

.PHONY: all test test-pe test-array test-uart test-top test-sizes clean

all: test

test: test-pe test-uart test-top test-sizes

test-pe: $(VVP_PE)
	$(VVP) $(VVP_PE)

test-uart: $(VVP_UART)
	$(VVP) $(VVP_UART)

test-top: $(VVP_TOP)
	@out=$$($(VVP) $(VVP_TOP) 2>&1); echo "$$out"; echo "$$out" | grep -q "tokyo_mac_top_tb PASSED"

# Default array sizes; override with ARRAY_SIZES="2 3 5"
ARRAY_SIZES ?= 2 3 4 8

test-sizes: test-array

test-array: $(foreach n,$(ARRAY_SIZES),$(BUILD_DIR)/systolic_array_tb_N$(n).vvp)
	@set -e; \
	for n in $(ARRAY_SIZES); do \
	  echo "========== systolic_array_tb N=$$n =========="; \
	  out=$$($(VVP) $(BUILD_DIR)/systolic_array_tb_N$$n.vvp 2>&1); \
	  echo "$$out"; \
	  echo "$$out" | grep -q "0 failed" || exit 1; \
	done

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(VVP_PE): rtl/mac_pe.sv $(TB_PE) | $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -o $@ rtl/mac_pe.sv $(TB_PE)

$(VVP_UART): rtl/uart.sv $(TB_UART) | $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -o $@ rtl/uart.sv $(TB_UART)

$(VVP_TOP): $(RTL) $(TB_TOP) | $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -o $@ $(RTL) $(TB_TOP)

$(BUILD_DIR)/systolic_array_tb_N%.vvp: $(RTL) $(TB_PKG) $(TB_ARRAY) | $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -DARRAY_N=$* -s systolic_array_top -o $@ $(RTL) $(TB_PKG) $(TB_ARRAY)

clean:
	rm -rf $(BUILD_DIR)
