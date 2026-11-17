"""Exercise the real C parser with adversarial and nested FAT Mach-O fixtures."""
import ctypes, pathlib, struct, subprocess, tempfile, sys
root = pathlib.Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory() as work:
    work = pathlib.Path(work)
    library = work / 'parser.so'
    subprocess.run(['cc', '-shared', '-fPIC', '-Wall', '-Wextra', '-Werror', str(root/'AppVault/Decryption/MachODecrypt.c'), '-o', str(library)], check=True)
    lib = ctypes.CDLL(str(library))
    lib.AVInspectMachO.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_size_t]
    def inspect(data):
        path = work/'binary'; path.write_bytes(data)
        error = ctypes.create_string_buffer(512)
        return lib.AVInspectMachO(str(path).encode(), error, 512)
    def macho(cryptid=1, off=16384, length=32):
        header = struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 2, 1, 24, 0, 0)
        cmd = struct.pack('<6I', 0x2c, 24, off, length, cryptid, 0)
        return (header+cmd).ljust(16416, b'\0')
    assert inspect(b'ordinary resource') == 0
    assert inspect(macho()) == 1
    assert inspect(macho(0)) == 0
    assert inspect(macho(off=0xffffffff)) == -1
    assert inspect(macho(length=0xffffffff)) == -1
    assert inspect(macho(length=0)) == -1
    assert inspect(macho()[:40]) == -1
    bad = bytearray(macho()); struct.pack_into('<I', bad, 36, 0)
    assert inspect(bad) == -1
    fat = struct.pack('>2I', 0xcafebabe, 1) + struct.pack('>5I', 0x100000c, 0, 16384, 16416, 14)
    assert inspect(fat.ljust(16384,b'\0')+macho()) == 1
    assert inspect(fat) == -1
    overlap = struct.pack('>2I', 0xcafebabe, 2) + struct.pack('>5I', 0x100000c,0,16384,16416,14)*2
    assert inspect(overlap.ljust(16384,b'\0')+macho()) == -1
    if sys.platform != 'darwin':
        source, output = work/'source', work/'output'
        source.write_bytes(macho()); output.write_bytes(macho())
        error = ctypes.create_string_buffer(512)
        assert lib.AVDecryptMachO(str(source).encode(), str(output).encode(), error, 512) == -1
        assert output.read_bytes() == macho(), 'Failed decryption must not clear cryptid'
    print('PASS: plaintext/encrypted, invalid commands/ranges, truncated and overlapping FAT fixtures')
