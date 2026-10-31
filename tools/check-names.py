#!/usr/bin/env python3
"""Names are never translated or bent in the core's language tables (owner,
2026-10-31): Supermodel, Model 3, MAME, OpenGL and every other program,
chip, machine, game or company name stay as they are written, in all 26
languages. A language whose grammar puts endings on names says the sentence
with a common noun beside the name instead ("emulatoru Supermodel",
"Model 3 -koneen", "NVRAM-mappen i Supermodel"). Chimera's own
tools/check-proper-nouns.py checks Chimera's names in Chimera's tables;
this checks this core's names (and Chimera's) in this core's tables.

A text fails when:

- a name its English text holds is not in it, written as in English;
- a letter of a script that writes words with spaces between them (Latin,
  Greek, Cyrillic) touches a name on either side ("Supermodela",
  "Supermodels", "Model 3s"); Chinese, Japanese and Korean put their
  particles straight after a word in their own script, which leaves the
  name whole, and are allowed;
- a name is followed by an apostrophe or a colon and letters (a case
  ending set off: "Supermodel'in", "Model 3:n");
- a name is followed by a hyphen and one to three letters (a case ending
  or an article: "Model 3-at", "OpenGL-ul"). A hyphen and a longer word is
  a compound with a common noun ("Model 3-spel", "OpenGL-megvalositasa")
  and is allowed, as Chimera's tables have "Chimera-ohjelman".

  tools/check-names.py [<languages folder>]

Prints each one as language key: what, text, and exits 1 when there is
any."""
import json
import os
import re
import sys

here = os.path.dirname(os.path.abspath(__file__))
folder = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "waterbox", "languages")
config = os.path.join(here, "..", "waterbox", "waterbox.config")

# the core's own name, from the package's declaration
with open(config, encoding="utf-8") as f:
    core_name = json.load(f)["coreName"]
# the names this core's texts use, and Chimera's (tools/check-proper-nouns.py)
NAMES = sorted({core_name, "Supermodel", "Model 3", "MAME", "OpenGL", "Sega", "Real3D", "Mesa", "llvmpipe",
                "Chimera", "TAStudio", "GitHub", "Lua", "Windows", "Linux", "macOS", "Vulkan", "Direct3D",
                "SQLite", "miniBox", "ffmpeg", "Qt", "Wayland"}, key=len, reverse=True)

# letters of the scripts that leave a space between words
WORD = "A-Za-z\u00c0-\u024f\u0370-\u03ff\u1f00-\u1fff\u0400-\u052f"


def whole(name):
    return re.compile("(?<![" + WORD + "])" + re.escape(name) + "(?![" + WORD + "])")


def bent(name):
    n = re.escape(name)
    return re.compile("[" + WORD + "]" + n + "|" + n + "[" + WORD + "]|" + n + "['\u2019:][" + WORD + "]|"
                      + n + "-[" + WORD + "]{1,3}(?![" + WORD + "])")


def texts(path):
    """a table's texts, a key's plural forms as one text"""
    with open(path, encoding="utf-8") as f:
        table = json.load(f)["texts"]
    return {k: " | ".join(v.values()) if isinstance(v, dict) else v for k, v in table.items()}


english = texts(os.path.join(folder, "en.json"))
names_in = {k: [n for n in NAMES if whole(n).search(v)] for k, v in english.items()}
bad = 0
tables = sorted(n for n in os.listdir(folder) if n.endswith(".json"))
for table in tables:
    code = table[:-5]
    for key, text in sorted(texts(os.path.join(folder, table)).items()):
        flat = text.replace("\n", " ")
        if code != "en":
            for n in names_in.get(key, []):
                if not whole(n).search(text):
                    print("%s %s: %s is not there as itself: %s" % (code, key, n, flat))
                    bad += 1
        # file names are not names in a sentence (vf3.zip, <game>.nv); English's own "Supermodel's" is
        # English's grammar, as Chimera's English keeps "Chimera's"
        bare = re.sub(r"\S*[./*<>]\S*", "", text)
        if code == "en":
            bare = re.sub("['\u2019]s(?![" + WORD + "])", "", bare)
        for n in NAMES:
            m = bent(n).search(bare)
            if m:
                print("%s %s: %s is bent (%s): %s" % (code, key, n, m.group(0), flat))
                bad += 1
print("%d tables, %d names, %d texts with a name changed" % (len(tables), len(NAMES), bad), file=sys.stderr)
sys.exit(1 if bad else 0)
