#!/usr/bin/env python3
"""Assemble an SD card folder (and optionally a zip) for the Pocket from a compiled core: the JSON / text tree of the
dist folder (--dist: Cores/<core>/..., Platforms/, Assets/) plus the bitstream, bit-reversed into
Cores/<core>/bitstream.rbf_r (the Pocket loads bitstreams with the bit order of every byte reversed). No BIOS or game
files are copied: the BIOS stays the user's Assets/saturn/common/boot.rom.

usage: package.py --rbf src/fpga/output_files/ap_core.rbf --dist dist --core akoaysigod.Saturn --out SDROOT [--zip FILE.zip]
"""
import argparse
import hashlib
import os
import shutil
import sys
import zipfile


def reverse_bits(data):
    table = bytes(int('{:08b}'.format(b)[::-1], 2) for b in range(256))
    return data.translate(table)


def write_zip(root, path):
    """The folder's files and folders (empty ones too) with paths relative to it, deflated (.rbf_r stored)."""
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with zipfile.ZipFile(path, 'w') as z:
        for top, dirs, files in os.walk(root):
            dirs.sort()
            if top != root:
                z.write(top, os.path.relpath(top, root).replace(os.sep, '/') + '/')
            for name in sorted(files):
                if name == '.DS_Store':
                    continue
                full = os.path.join(top, name)
                arc = os.path.relpath(full, root).replace(os.sep, '/')
                stored = name.lower().endswith(('.rbf_r', '.bin', '.rom'))
                z.write(full, arc, compress_type=zipfile.ZIP_STORED if stored else zipfile.ZIP_DEFLATED)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rbf', required=True)
    ap.add_argument('--dist', required=True)
    ap.add_argument('--core', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--zip')
    a = ap.parse_args()
    if not a.rbf.endswith('.rbf'):
        sys.exit('--rbf must be the Quartus .rbf')
    raw = open(a.rbf, 'rb').read()
    if os.path.exists(a.out):
        shutil.rmtree(a.out)
    shutil.copytree(a.dist, a.out)
    core_dir = os.path.join(a.out, 'Cores', a.core)
    if not os.path.isdir(core_dir):
        sys.exit('no Cores/%s in %s' % (a.core, a.dist))
    for top, dirs, files in os.walk(a.out):
        for name in files:
            full = os.path.join(top, name)
            rel = os.path.relpath(full, a.out).replace(os.sep, '/')
            if name.lower().endswith(('.bin', '.rom', '.cue', '.rbf_r')) and not (
                    rel == 'Platforms/_images/' + name or (rel.startswith('Cores/%s/' % a.core) and name == 'icon.bin')):
                sys.exit('unexpected file in the dist tree: %s' % full)
    bs = reverse_bits(raw)
    with open(os.path.join(core_dir, 'bitstream.rbf_r'), 'wb') as f:
        f.write(bs)
    print('rbf   %s md5 %s' % (a.rbf, hashlib.md5(raw).hexdigest()))
    print('rbf_r %s md5 %s' % (os.path.join(core_dir, 'bitstream.rbf_r'), hashlib.md5(bs).hexdigest()))
    if a.zip:
        write_zip(a.out, a.zip)
        print('zip   %s md5 %s' % (a.zip, hashlib.md5(open(a.zip, 'rb').read()).hexdigest()))


if __name__ == '__main__':
    main()
