import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import random

# Opcode constants from int8_mac_instr_pkg.sv
OP_ILLEGAL  = 0
OP_MAC8     = 1
OP_MAC8_ACC = 2
OP_MUL8     = 3
OP_CLIP8    = 4
OP_SIMD_DOT = 5

async def reset_dut(dut):
    dut.rst_ni.value = 0
    dut.rs1_i.value = 0
    dut.rs2_i.value = 0
    dut.rd_i.value = 0
    dut.opcode_i.value = 0
    dut.hartid_i.value = 0
    dut.id_i.value = 0
    dut.rd_addr_i.value = 0
    
    await Timer(20, units="ns")
    dut.rst_ni.value = 1
    await RisingEdge(dut.clk_i)

def get_signed_bytes(val):
    """Extract 4 signed bytes from a 32-bit integer"""
    bytes_list = []
    for i in range(4):
        byte = (val >> (i * 8)) & 0xFF
        if byte >= 128:
            byte -= 256
        bytes_list.append(byte)
    return bytes_list

@cocotb.test()
async def test_simd_dot(dut):
    """Test SIMD Dot Product operation"""
    clock = Clock(dut.clk_i, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    
    # Run 1000 random vectors
    for i in range(1000):
        # Generate inputs
        rs1_bytes = [random.randint(-128, 127) for _ in range(4)]
        rs2_bytes = [random.randint(-128, 127) for _ in range(4)]
        acc_val = random.randint(-2147483648, 2147483647)
        
        # Pack into 32-bit integers
        rs1_val = 0
        rs2_val = 0
        for b_idx in range(4):
            rs1_val |= (rs1_bytes[b_idx] & 0xFF) << (b_idx*8)
            rs2_val |= (rs2_bytes[b_idx] & 0xFF) << (b_idx*8)
            
        # Drive DUT
        dut.rs1_i.value = rs1_val
        dut.rs2_i.value = rs2_val
        dut.rd_i.value = acc_val
        dut.opcode_i.value = OP_SIMD_DOT
        
        # Wait for clock edge
        await RisingEdge(dut.clk_i)
        
        # Wait for next clock edge to capture registered output
        # The design registers inputs? No, it's combinational logic -> registered output
        # Cycle 1: Inputs driven -> Logic computes -> Register inputs capture at end of cycle 1?
        # Looking at RTL: 
        #   always_comb calculates result_comb
        #   always_ff captures result_comb into result_q
        # So we drive inputs, wait for posedge, result_q updates.
        # We can check result_o immediately after the posedge (with small delta delay provided by ReadOnly/Monitor usually)
        # But in simple driver, await RisingEdge returns after the edge.
        
        # Need to wait one clock cycle for the pipeline
        await RisingEdge(dut.clk_i) 
        
        # Calculate Expected Model
        dot_product = 0
        for b in range(4):
            dot_product += rs1_bytes[b] * rs2_bytes[b]
        
        expected = dot_product + acc_val
        
        # Handle 32-bit overflow for python comparison
        if expected > 2147483647:
            expected -= 4294967296
        elif expected < -2147483648:
            expected += 4294967296
            
        # Check Output
        got = dut.result_o.value.signed_integer
        valid = dut.valid_o.value
        
        assert valid == 1, f"Output should be valid for SIMD_DOT"
        assert got == expected, \
            f"Iter {i}: Mismatch! rs1={rs1_bytes}, rs2={rs2_bytes}, acc={acc_val}\n" \
            f"Expected: {expected}, Got: {got}"

    dut._log.info("SIMD_DOT verification passed (1000 vectors)")

@cocotb.test()
async def test_mac8_legacy(dut):
    """Regression test for original MAC8 instruction"""
    clock = Clock(dut.clk_i, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    
    # Simple test for MAC8
    rs1_byte = 10
    rs2_byte = -5
    acc_byte = 20
    
    dut.rs1_i.value = rs1_byte & 0xFF
    dut.rs2_i.value = rs2_byte & 0xFF
    dut.rd_i.value = acc_byte & 0xFF
    dut.opcode_i.value = OP_MAC8
    
    await RisingEdge(dut.clk_i)
    await RisingEdge(dut.clk_i)
    
    expected = (rs1_byte * rs2_byte) + acc_byte # 10*-5 + 20 = -30
    got = dut.result_o.value.signed_integer
    # Result is in lower 8 bits, sign extended?
    # RTL: result_comb = {{24{sum_9bit[7]}}, sum_9bit[7:0]};
    
    assert got == expected, f"MAC8 failed. Expected {expected}, got {got}"
