using System.Buffers.Binary;

namespace Vinculum.Rendering;

/// Decodes the VDL1 wire format (docs/DISPLAYLIST.md) — the C# twin of Swift
/// DisplayListWire and Kotlin VinculumWire. Consumes an UNTRUSTED buffer: returns
/// null (never throws) on bad magic, truncation, unknown tag, or a forged count;
/// never allocates on an untrusted length.
public static class VinculumWire
{
    public static DisplayList? Decode(byte[] b)
    {
        if (b.Length < 20) return null;
        if (b[0] != (byte)'V' || b[1] != (byte)'D' || b[2] != (byte)'L' || b[3] != (byte)'1') return null;
        try
        {
            int p = 4;
            float F() { var v = BinaryPrimitives.ReadSingleLittleEndian(b.AsSpan(p)); p += 4; return v; }
            uint U() { var v = BinaryPrimitives.ReadUInt32LittleEndian(b.AsSpan(p)); p += 4; return v; }
            byte B() => b[p++];
            uint RGBA() { uint r = B(), g = B(), bl = B(), a = B(); return (a << 24) | (r << 16) | (g << 8) | bl; }

            List<Seg> Segs()
            {
                uint n = U();
                if (n > (uint)(b.Length - p + 1)) throw new InvalidOperationException("bad segCount");
                var segs = new List<Seg>((int)Math.Min(n, (uint)b.Length));
                for (uint i = 0; i < n; i++)
                {
                    byte so = B();
                    segs.Add(so switch
                    {
                        0 or 1 => new Seg((SegOp)so, new[] { F(), F() }),
                        2 => new Seg(SegOp.Quad, new[] { F(), F(), F(), F() }),
                        3 => new Seg(SegOp.Cubic, new[] { F(), F(), F(), F(), F(), F() }),
                        4 => new Seg(SegOp.Close, Array.Empty<float>()),
                        _ => throw new InvalidOperationException("bad seg op"),
                    });
                }
                return segs;
            }

            float width = F(), ascent = F(), descent = F();
            uint opCount = U();
            if (opCount > (uint)b.Length) return null;   // untrusted count
            var ops = new List<Op>((int)Math.Min(opCount, (uint)b.Length));
            for (uint i = 0; i < opCount; i++)
            {
                switch (B())
                {
                    case 0: { uint c = RGBA(); ops.Add(new FillPath(Segs(), c)); break; }   // rgba THEN segs
                    case 1: { uint c = RGBA(); ops.Add(new FillRect(F(), F(), F(), F(), c)); break; }
                    case 2: { uint c = RGBA(); float w = F(); byte cap = B(), join = B(); ops.Add(new StrokePath(Segs(), w, cap, join, c)); break; }
                    default: return null;
                }
            }
            return new DisplayList(width, ascent, descent, ops);
        }
        catch { return null; }
    }
}
