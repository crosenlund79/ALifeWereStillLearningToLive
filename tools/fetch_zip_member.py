"""Extract single files from a remote zip (e.g. Godot's ~1 GB export templates) via HTTP range requests.

Usage: python3 fetch_zip_member.py URL OUT_DIR MEMBER [MEMBER...]
"""
import struct, subprocess, sys, zlib, os

url, out_dir, members = sys.argv[1], sys.argv[2], sys.argv[3:]


def fetch(start, end):
    return subprocess.run(["curl", "-sSLf", "-r", f"{start}-{end}", url], check=True, capture_output=True).stdout


head = subprocess.run(["curl", "-sSLI", url], check=True, capture_output=True, text=True).stdout
length = int([l for l in head.lower().splitlines() if l.startswith("content-length:")][-1].split(":")[1])
tail = fetch(length - 65536, length - 1)
eocd = tail.rfind(b"PK\x05\x06")
cd_size, cd_offset = struct.unpack("<II", tail[eocd + 12:eocd + 20])
if cd_offset == 0xFFFFFFFF:  # zip64
    loc = tail.rfind(b"PK\x06\x07")
    z64_off = struct.unpack("<Q", tail[loc + 8:loc + 16])[0]
    z64 = fetch(z64_off, z64_off + 56)
    cd_size, cd_offset = struct.unpack("<QQ", z64[40:56])
cd = fetch(cd_offset, cd_offset + cd_size - 1)

entries, i = {}, 0
while cd[i:i + 4] == b"PK\x01\x02":
    method, = struct.unpack("<H", cd[i + 10:i + 12])
    csize, usize = struct.unpack("<II", cd[i + 20:i + 28])
    nlen, elen, clen = struct.unpack("<HHH", cd[i + 28:i + 34])
    off, = struct.unpack("<I", cd[i + 42:i + 46])
    name = cd[i + 46:i + 46 + nlen].decode()
    extra = cd[i + 46 + nlen:i + 46 + nlen + elen]
    j = 0
    while j < len(extra):  # zip64 extended info
        hid, hlen = struct.unpack("<HH", extra[j:j + 4])
        if hid == 1:
            vals, k = extra[j + 4:j + 4 + hlen], 0
            if usize == 0xFFFFFFFF: usize, = struct.unpack("<Q", vals[k:k + 8]); k += 8
            if csize == 0xFFFFFFFF: csize, = struct.unpack("<Q", vals[k:k + 8]); k += 8
            if off == 0xFFFFFFFF: off, = struct.unpack("<Q", vals[k:k + 8])
        j += 4 + hlen
    entries[name] = (method, csize, off)
    i += 46 + nlen + elen + clen

os.makedirs(out_dir, exist_ok=True)
for member in members:
    method, csize, off = entries[member]
    head = fetch(off, off + 29)
    nlen, elen = struct.unpack("<HH", head[26:30])
    data = fetch(off + 30 + nlen + elen, off + 30 + nlen + elen + csize - 1)
    if method == 8:
        data = zlib.decompress(data, -15)
    with open(os.path.join(out_dir, os.path.basename(member)), "wb") as f:
        f.write(data)
    print(member, len(data))
