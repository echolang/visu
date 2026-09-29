#!/usr/bin/env python3
"""Keep the committed bytes of every baked program not named on the command line.

    bakemerge.py <old.eco> <new.eco> [program ...]

The local glslang / spirv-cross emit different bytes for unchanged sources; this keeps the
committed ones so a rebake only changes the programs whose sources actually changed.
"""
import re, sys
PAT = re.compile(r"(    if \(\$program == '([^']+)' && \$kind == visu::graphics::ShaderKind::(\w+)\) \{\n        return )((?:visu::graphics::hexBytes\()?'(?:[^'\\]|\\.)*'\)?)(;\n    \}\n)", re.S)
old_path, new_path = sys.argv[1], sys.argv[2]
keep_new = set(sys.argv[3:])
old = open(old_path).read()
arms_old = old.split('#[else]')
new = open(new_path).read()
arms_new = new.split('#[else]')
assert len(arms_old) == 2 and len(arms_new) == 2
out = []
for ao, an in zip(arms_old, arms_new):
    olds = {(m.group(2), m.group(3)): m.group(4) for m in PAT.finditer(ao)}
    def sub(m):
        key = (m.group(2), m.group(3))
        if key in olds and m.group(2) not in keep_new:
            return m.group(1) + olds[key] + m.group(5)
        return m.group(0)
    out.append(PAT.sub(sub, an))
open(new_path, 'w').write('#[else]'.join(out))
