# FPGA 7020 AC702 SSB TDOA

This repository contains a Vivado FPGA project for SSB signal processing and TDOA-related modules on the 7020/AC702 platform.

## Contents

- `final.srcs/`: Vivado source files, testbenches, constraints, and IP configuration files.
- `final.ip_user_files/`: Vivado IP helper files, memory initialization files, and simulation scripts.
- `final.hw/`: Hardware manager layout/configuration files.
- Top-level HDL and MATLAB files: core source modules and `tdoa_receiver_cn2.m`.

## Notes

Vivado generated output and large simulation artifacts are intentionally not committed. This includes `final.cache/`, `final.runs/`, `final.sim/`, waveform files such as `.vcd` and `.wdb`, and implementation artifacts such as `.dcp` and `.bit`.

Open or regenerate the project with Vivado using the committed source, constraint, and IP configuration files.
