# Makefile for conv testbench with VCS

# Project paths
PROJECT_ROOT := $(shell cd ../.. && pwd)
SET_ENV_SCRIPT := $(PROJECT_ROOT)/set_env.sh
FILELIST := $(PROJECT_ROOT)/filelist.f

# Source set_env.sh to get PROJECT_PATH
# Use shell to source the script and export the variable
SHELL := /bin/bash
export PROJECT_PATH := $(shell source $(SET_ENV_SCRIPT) > /dev/null 2>&1 && echo $$PROJECT_PATH)

# Source files
TB_DIR = .
DATA_DIR = ../data

TB_SRCS = $(TB_DIR)/ut_conv.sv

# VCS settings
VCS = vcs
VCS_FLAGS = -full64 \
            -sverilog \
            -timescale=1ns/1ps \
            +v2k \
            -debug_access+all \
            -lca \
            -kdb \
            +lint=TFIPC-L \
            +warn=noUFTMD \
            +incdir+$(PROJECT_PATH)/data \
            -P ${VERDI_HOME}/share/PLI/VCS/LINUX64/novas.tab \
            ${VERDI_HOME}/share/PLI/VCS/LINUX64/pli.a

# Simulation flags for FSDB dumping
SIM_FLAGS = +vcs+flush+all \
            +fsdbfile+ut_conv.fsdb \
            +PROJECT_PATH=$(PROJECT_PATH)

# Output files
SIMV = simv
VPD_FILE = vcdplus.vpd
FSDB_FILE = ut_conv.fsdb
LOG_FILE = sim.log

.PHONY: all compile sim clean wave help check_env

all: sim

# Check if PROJECT_PATH is set
check_env:
	@if [ -z "$(PROJECT_PATH)" ]; then \
		echo "Error: PROJECT_PATH not set!"; \
		echo "Attempting to source $(SET_ENV_SCRIPT)..."; \
		exit 1; \
	fi
	@echo "PROJECT_PATH is set to: $(PROJECT_PATH)"

# Compile with VCS using filelist
compile: check_env $(FILELIST) $(TB_SRCS)
	@echo "Compiling with VCS using filelist..."
	@echo "Using filelist: $(FILELIST)"
	$(VCS) $(VCS_FLAGS) -f $(FILELIST) $(TB_SRCS) -o $(SIMV)
	@echo "Compilation complete!"

# Run simulation
sim: compile
	@echo "Running simulation..."
	./$(SIMV) $(SIM_FLAGS) | tee $(LOG_FILE)
	@echo "Simulation complete!"

# Run simulation with waveform dump
sim_wave: compile
	@echo "Running simulation with waveform dump..."
	./$(SIMV) $(SIM_FLAGS) | tee $(LOG_FILE)
	@echo "Simulation complete!"
	@echo "FSDB waveform saved to ut_conv.fsdb"

# View waveform with DVE
wave: $(VPD_FILE)
	dve -vpd $(VPD_FILE) &

# View waveform with Verdi
verdi: 
	@if [ ! -f $(FSDB_FILE) ]; then \
		echo "Error: $(FSDB_FILE) not found!"; \
		echo "Please run 'make sim' first to generate the waveform."; \
		exit 1; \
	fi
	@echo "Opening Verdi to view waveform..."
	verdi -ssf $(FSDB_FILE) -nologo &

# Clean generated files
clean:
	rm -rf $(SIMV) $(SIMV).daidir csrc ucli.key
	rm -f $(VPD_FILE) $(FSDB_FILE) $(LOG_FILE)
	rm -f *.log *.vpd *.fsdb *.vcd
	rm -rf verdiLog novas* *fsdb* *.conf
	rm -rf verdi_config_file

help:
	@echo "Available targets:"
	@echo "  make compile   - Compile with VCS using filelist.f"
	@echo "  make sim       - Compile and run simulation"
	@echo "  make sim_wave  - Run simulation with waveform dump"
	@echo "  make wave      - Open waveform viewer (DVE)"
	@echo "  make verdi     - Open waveform viewer (Verdi)"
	@echo "  make clean     - Remove generated files"
	@echo "  make check_env - Check if PROJECT_PATH is set"
	@echo ""
	@echo "Note: Makefile automatically sources $(SET_ENV_SCRIPT)"
	@echo "      Current PROJECT_PATH: $(PROJECT_PATH)"
