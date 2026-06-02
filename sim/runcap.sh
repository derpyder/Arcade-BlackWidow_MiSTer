#!/usr/bin/env bash
# Build + run the Black Widow / Gravitar AVG render tb -> <game>_frame.txt.
# usage: ./runcap.sh [hexfile] [cap_lo_us] [cap_hi_us] [stop] [capall]
set -e
GHDL="C:/Users/mattl/bin/ghdl/bin/ghdl.exe"
HEX="${1:-bwidow_dl.hex}"
CAPLO="${2:-40000}"
CAPHI="${3:-70000}"
STOP="${4:-72ms}"
CAPALL="${5:-0}"
cd "$(dirname "$0")"
rm -rf work_r && mkdir -p work_r
# Sim substitutes (dpram_sim/ram_2k_sim) replace the real altsyncram leaves.
$GHDL -a --std=08 -frelaxed -fsynopsys --workdir=work_r \
    ../rtl/pkg_bwidow.vhd \
    dpram_sim.vhd ram_2k_sim.vhd \
    ../rtl/ram2k.vhd ../rtl/dpram2k.vhd \
    ../rtl/pokey.vhd ../rtl/earom.vhd \
    ../rtl/vecrom.vhd ../rtl/pgmrom.vhd \
    ../rtl/avg/vector_drawer.vhd ../rtl/avg/avg.vhd \
    ../rtl/t65/T65_Pack.vhd ../rtl/t65/T65_ALU.vhd ../rtl/t65/T65_MCode.vhd ../rtl/t65/T65.vhd \
    ../rtl/bwidow.vhd tb_bwidow_render.vhd
$GHDL -e --std=08 -frelaxed -fsynopsys --workdir=work_r tb_bwidow_render
$GHDL -r --std=08 -frelaxed -fsynopsys --workdir=work_r tb_bwidow_render \
    -gHEXFILE=$HEX -gCAP_LO_US=$CAPLO -gCAP_HI_US=$CAPHI -gCAPALL=$CAPALL \
    --ieee-asserts=disable --stop-time=$STOP
