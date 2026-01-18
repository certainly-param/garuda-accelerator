# Contributing to Garuda

Contributions are welcome. This document provides guidelines for contributing to the Garuda RISC-V ML accelerator project.

## How to Contribute

### Reporting Issues

- Use GitHub Issues to report bugs or request features
- Provide a clear description of the issue or feature request
- For bugs, include steps to reproduce and expected vs actual behavior
- For RTL issues, include testbench code that demonstrates the problem

### Code Contributions

#### Development Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/certainly-param/garuda-accelerator.git
   cd garuda-accelerator
   git submodule update --init --recursive
   ```

2. **Install dependencies:**
   - **Icarus Verilog** (for basic simulations)
     - Ubuntu/Debian: `sudo apt-get install iverilog`
     - macOS: `brew install icarus-verilog`
   - **Verilator** (for advanced verification)
     - Ubuntu/Debian: `sudo apt-get install verilator`
   - **Yosys** (for synthesis)
     - Ubuntu/Debian: `sudo apt-get install yosys`

3. **Verify setup:**
   ```bash
   # Run a quick test
   iverilog -g2012 -o sim_test.vvp garuda/tb/tb_register_rename_table.sv garuda/rtl/register_rename_table.sv
   vvp sim_test.vvp
   ```

#### Coding Standards

- **SystemVerilog**: Follow SystemVerilog 2012 standard
- **Naming conventions**:
  - Module names: `snake_case` (e.g., `int8_mac_unit`)
  - Signals: `snake_case` with suffix indicating direction (`_i` for input, `_o` for output, `_q` for registered)
  - Constants: `UPPER_SNAKE_CASE`
- **Code organization**: One module per file, file name matches module name
- **Comments**: Document all modules, parameters, and non-obvious logic
- **Icarus compatibility**: Code must compile with Icarus Verilog (avoid advanced SystemVerilog features not supported by Icarus)

#### Testbench Requirements

- All new RTL modules must include a testbench
- Testbenches should be self-verifying (use `$display` or assertions)
- Testbenches should run with Icarus Verilog: `iverilog -g2012`
- Add new testbenches to `ci/run_iverilog_sims.sh` for CI integration

#### Submission Process

1. **Fork the repository** and create a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes:**
   - Write or modify RTL modules
   - Add testbenches for new functionality
   - Update documentation as needed

3. **Test your changes:**
   ```bash
   # Run all simulations
   bash ci/run_iverilog_sims.sh
   ```

4. **Commit with clear messages:**
   ```bash
   git commit -m "Add feature: brief description"
   ```

5. **Push and create a Pull Request:**
   - Ensure CI passes (all testbenches run successfully)
   - Describe your changes in the PR description
   - Reference any related issues

### Areas for Contribution

#### RTL Improvements
- Performance optimizations
- Area/power reductions
- New instruction implementations
- Bug fixes

#### Verification
- Additional testbenches
- Coverage improvements
- Integration tests
- Formal verification

#### Documentation
- Code comments and module documentation
- Architecture diagrams
- Tutorial examples
- Use case documentation

#### Software Tools
- Compiler support for custom instructions
- Benchmark suites
- Performance analysis tools

#### Synthesis & PPA
- FPGA/ASIC synthesis scripts
- Timing closure improvements
- Area optimizations

## Project Structure

```
garuda-accelerator/
├── garuda/
│   ├── rtl/          # RTL source files
│   ├── tb/           # Testbenches
│   ├── dv/           # Cocotb verification
│   └── synth/        # Synthesis scripts
├── ci/               # CI helper scripts
└── .github/          # GitHub Actions workflows
```

## Code Review Process

- All PRs require review before merging
- Reviewers will check:
  - Code quality and adherence to standards
  - Test coverage (testbenches must pass)
  - Documentation completeness
  - CI status (must pass)

## Questions?

- Open a GitHub Issue for questions about contributing
- Check existing issues before creating a new one
- Be respectful and constructive in discussions

Thank you for contributing to Garuda!
