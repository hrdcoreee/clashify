#!/usr/bin/env python3
"""
patch_macho.py - Flawless Mach-O Platform & CodeDirectory Patcher for iOS 14 Jailbreak

Why this is required:
1. Upstream darwin-arm64 Golang binary declares platform = 1 (macOS) in LC_BUILD_VERSION.
   dyld on iOS strictly enforces platform matching and refuses to link iOS system dylibs.
2. In Golang binaries, all code/data modifications occur within Page 0 (offsets 0..4096).
   Pages 1..6464 remain 100% byte-identical to upstream.
3. Apple's XNU kernel and AMFI verify:
   - SHA256 page hashes for every 4096-byte chunk.
   - execSegBase & execSegLimit matching the actual __TEXT segment (filesize: 13352960).
   If execSegLimit does not match __TEXT segment, XNU immediately terminates with SIGKILL (zsh: killed).

This script:
- Converts LC_BUILD_VERSION platform from macOS (1) to iOS (2), iOS 14.0.
- Normalizes LC_LOAD_DYLIB framework paths (stripping /Versions/A/).
- Preserves upstream CodeDirectory structure, flags, and execSegLimit.
- Recomputes and updates the Page 0 SHA256 hash in-place.
- Verifies that all 6,465 page hashes are 100% valid.
"""

import sys
import struct
import hashlib

def patch_macho(binary_path, output_path=None):
    if output_path is None:
        output_path = binary_path

    print(f"[*] Processing Mach-O binary: {binary_path}")
    with open(binary_path, 'rb') as f:
        data = bytearray(f.read())

    magic = struct.unpack('<I', data[:4])[0]
    if magic != 0xfeedfacf:
        raise ValueError(f"[-] Unsupported Mach-O magic: 0x{magic:x} (expected 0xfeedfacf 64-bit)")

    ncmds, sizeofcmds = struct.unpack('<II', data[16:24])
    offset = 32
    codesig_dataoff = None
    codesig_datasize = None
    patched_platform = False
    patched_dylibs = 0

    for i in range(ncmds):
        cmd, cmdsize = struct.unpack('<II', data[offset:offset+8])

        if cmd == 0x32: # LC_BUILD_VERSION
            platform, minos, sdk, ntools = struct.unpack('<IIII', data[offset+8:offset+24])
            if platform != 2:
                # Patch platform to iOS (2), minos 14.0 (0x000e0000), sdk 14.0 (0x000e0000)
                struct.pack_into('<III', data, offset + 8, 2, 0x000e0000, 0x000e0000)
                patched_platform = True
                print("[+] Converted LC_BUILD_VERSION platform: macOS (1) -> iOS (2), iOS 14.0")

        elif cmd == 0x0c: # LC_LOAD_DYLIB
            stroff = struct.unpack('<I', data[offset+8:offset+12])[0]
            dylib_bytes = data[offset+stroff:offset+cmdsize].split(b'\x00')[0]
            if b'/Versions/A/' in dylib_bytes:
                new_dylib = dylib_bytes.replace(b'/Versions/A/', b'/')
                slot_len = cmdsize - stroff
                data[offset+stroff:offset+cmdsize] = new_dylib + b'\x00' * (slot_len - len(new_dylib))
                print(f"[+] Normalized dylib: {dylib_bytes.decode()} -> {new_dylib.decode()}")
                patched_dylibs += 1

        elif cmd == 0x1d: # LC_CODE_SIGNATURE
            codesig_dataoff, codesig_datasize = struct.unpack('<II', data[offset+8:offset+16])

        offset += cmdsize

    if codesig_dataoff is None:
        raise ValueError("[-] LC_CODE_SIGNATURE load command not found")

    # Locate CodeDirectory in SuperBlob
    sb_magic, sb_len, sb_count = struct.unpack('>III', data[codesig_dataoff:codesig_dataoff+12])
    if sb_magic != 0xfade0cc0:
        raise ValueError(f"[-] Invalid SuperBlob magic: 0x{sb_magic:x}")

    cd_soff = None
    for i in range(sb_count):
        stype, soff = struct.unpack('>II', data[codesig_dataoff + 12 + i*8 : codesig_dataoff + 12 + (i+1)*8])
        if stype == 0: # CSSLOT_CODEDIRECTORY
            cd_soff = soff
            break

    if cd_soff is None:
        raise ValueError("[-] CodeDirectory blob index not found in SuperBlob")

    cd_abs_offset = codesig_dataoff + cd_soff
    cd_magic, cd_len, cd_ver, cd_flags, hashOffset, identOffset, nSpecial, nCode, codeLimit = struct.unpack(
        '>IIIIIIIII', data[cd_abs_offset:cd_abs_offset+36]
    )

    if cd_magic != 0xfade0c02:
        raise ValueError(f"[-] Invalid CodeDirectory magic: 0x{cd_magic:x}")

    print(f"[*] CodeDirectory info: nCodeSlots={nCode}, codeLimit={codeLimit}, hashOffset={hashOffset}")

    # Hash for page 0
    hash_start = cd_abs_offset + hashOffset
    new_page0_hash = hashlib.sha256(data[:4096]).digest()
    data[hash_start:hash_start+32] = new_page0_hash
    print(f"[+] Updated Page 0 SHA256 hash: {new_page0_hash.hex()}")

    # Verify all remaining page hashes match perfectly
    mismatches = 0
    for p in range(1, nCode):
        h_in_cd = bytes(data[hash_start + p*32 : hash_start + (p+1)*32])
        start = p * 4096
        end = min(start + 4096, codeLimit)
        h_actual = hashlib.sha256(data[start:end]).digest()
        if h_in_cd != h_actual:
            mismatches += 1

    if mismatches == 0:
        print(f"[✓] All {nCode} page hashes verified valid!")
    else:
        print(f"[!] Warning: {mismatches} page hash mismatches found (updating remaining...)")
        for p in range(1, nCode):
            start = p * 4096
            end = min(start + 4096, codeLimit)
            data[hash_start + p*32 : hash_start + (p+1)*32] = hashlib.sha256(data[start:end]).digest()

    with open(output_path, 'wb') as f:
        f.write(data)

    print(f"[+] Successfully saved patched binary: {output_path} ({len(data)} bytes)")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <binary_path> [output_path]")
        sys.exit(1)
    bin_p = sys.argv[1]
    out_p = sys.argv[2] if len(sys.argv) > 2 else bin_p
    patch_macho(bin_p, out_p)
