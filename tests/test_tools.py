"""Toolchain contracts, known encodings, and architectural corner cases."""
import random
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from mini_rv32_asm import assemble, AssemblyError, REGS
from rv32im_ref import CPU, divs, rems, s32, u32, legal

class AssemblerTests(unittest.TestCase):
    def test_known_encodings(self):
        self.assertEqual(assemble('addi a0,zero,1\nadd a1,a0,a0\nlui a2,0x12345\necall'),
                         [0x00100513,0x00a505b3,0x12345637,0x73])

    def test_standard_u_field(self):
        c=CPU(assemble('lui a0,0x80000\nauipc a1,1\necall')); c.run()
        self.assertEqual(c.x[10],0x80000000); self.assertEqual(c.x[11],4100)

    def test_full_width_li(self):
        rng=random.Random(32)
        for n in [-2147483648,-2049,-2048,-1,0,1,2047,2048,4095,0x7fffffff,0xffffffff]+[rng.getrandbits(32) for _ in range(100)]:
            with self.subTest(n=n):
                c=CPU(assemble(f'li a0,{n}\necall')); c.run(); self.assertEqual(c.x[10],u32(n))

    def test_labels_after_expansion(self):
        c=CPU(assemble('li a0,0x12345678\nj done\nli a0,0\ndone: mv a1,a0\necall')); c.run()
        self.assertEqual(c.x[11],0x12345678); self.assertEqual(c.steps,5)

    def test_abi_aliases(self):
        self.assertEqual(REGS['fp'],REGS['s0']); self.assertEqual(len({REGS[f'x{i}'] for i in range(32)}),32)

    def test_source_diagnostics(self):
        with self.assertRaisesRegex(AssemblyError,'line 3:.*shift'):
            assemble('# comment\nnop\nslli a0,a0,32')

    def test_rejects_invalid_inputs(self):
        for text in ['addi x32,x0,1','addi x1,x0,2048','addi x1,x0,-2049','slli x1,x0,-1',
                     'srai x1,x0,32','lui x1,0x100000','li x1,0x100000000','li x1,-2147483649',
                     'jal x1,missing','beq x1,x2,3','beq x1,x2,4096','jal x1,1048576',
                     'same:nop\nsame:nop','add x1,x2','mystery x1','.word 0x100000000']:
            with self.subTest(text=text), self.assertRaises(AssemblyError): assemble(text)

    def test_immediate_boundaries(self):
        assemble('addi x1,x0,-2048\naddi x2,x0,2047\nbeq x0,x0,-4096\njal x0,1048574')

    def test_pseudoinstructions(self):
        c=CPU(assemble('li a0,7\nmv a1,a0\nnot a2,a1\nneg a3,a1\nbeqz zero,done\nli a0,0\ndone: ecall')); c.run()
        self.assertEqual(c.x[10:14],[7,7,0xfffffff8,0xfffffff9])

class ReferenceTests(unittest.TestCase):
    def test_division_rounds_to_zero(self):
        for a,b,q,r in [(-7,3,-2,-1),(7,-3,-2,1),(-7,-3,2,-1),(7,3,2,1)]:
            self.assertEqual(s32(divs(a,b)),q); self.assertEqual(s32(rems(a,b)),r)

    def test_division_zero_and_overflow(self):
        for a in [0,1,0x80000000,0xffffffff]:
            self.assertEqual(divs(a,0),0xffffffff); self.assertEqual(rems(a,0),a)
        self.assertEqual(divs(0x80000000,0xffffffff),0x80000000)
        self.assertEqual(rems(0x80000000,0xffffffff),0)

    def test_division_identity_random(self):
        rng=random.Random(19)
        for _ in range(1000):
            a=s32(rng.getrandbits(32)); b=s32(rng.getrandbits(32)) or 1
            q=s32(divs(a,b)); r=s32(rems(a,b))
            self.assertEqual(a,b*q+r); self.assertLess(abs(r),abs(b))
            self.assertTrue(r==0 or (r<0)==(a<0))

    def test_x0(self):
        c=CPU(assemble('li zero,123\nadd a0,zero,zero\necall')); c.run()
        self.assertEqual(c.x[0],0); self.assertEqual(c.x[10],0)

    def test_fault_suppresses_younger_side_effects(self):
        c=CPU(assemble('li a0,99\n.word 0xffffffff\nsw a0,256(zero)\necall')); c.run()
        self.assertTrue(c.faulted); self.assertEqual(c.fault_cause,2); self.assertEqual(c.load32(256),0)

    def test_signed_memory_lanes(self):
        c=CPU(assemble('li a0,0x80ff7f01\nsw a0,256(zero)\nlb a1,259(zero)\nlhu a2,258(zero)\necall')); c.run()
        self.assertEqual(c.x[11],0xffffff80); self.assertEqual(c.x[12],0x80ff)

    def test_misaligned_no_partial_write(self):
        c=CPU(assemble('li a0,-1\nsw a0,257(zero)\necall')); c.run()
        self.assertEqual(c.fault_cause,6); self.assertEqual(c.mem,bytearray(65536))

    def test_uart_and_unmapped_memory(self):
        c=CPU(assemble('li a0,0x10000000\nli a1,65\nsb a1,0(a0)\nlw a2,0(a0)\necall')); c.run()
        self.assertEqual(c.uart,b'A'); self.assertEqual(c.x[12],0); self.assertEqual(len(c.mem),65536)

    def test_timeout(self):
        c=CPU(assemble('here:j here'))
        with self.assertRaisesRegex(RuntimeError,'did not halt'): c.run(10)

    def test_strict_reserved_encodings(self):
        for ins in [0xffffffff,0x02001093,0x04000033,0x00003083,0xc0002073,0x100f]:
            self.assertFalse(legal(ins),f'{ins:08x}')

if __name__=='__main__': unittest.main()
