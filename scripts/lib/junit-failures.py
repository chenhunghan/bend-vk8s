#!/usr/bin/env python3
"""Each failed test of a sonobuoy result archive, with its failure message.

usage: junit-failures.py ARCHIVE.tar.gz [MAX_LINES]

Reads plugins/e2e/results/global/junit_*.xml inside the archive (the e2e
plugin's JUnit report) and prints, for every testcase with a <failure> or
an <error>: its name, its time, the message (at most MAX_LINES lines,
default 60, the first 20 and the last 40 when longer: a Gomega failure
ends with the status it saw and the line it failed at) and the last 30
lines of its system-err (Ginkgo's timeline of the test). Prints nothing
for an archive without failures; exits 0 unless the archive is unreadable.
"""
import sys
import tarfile
import xml.etree.ElementTree as ET


def clip(text, limit):
    lines = (text or "").strip().splitlines()
    if len(lines) <= limit:
        return lines
    head = limit // 3
    tail = limit - head
    return lines[:head] + ["... (%d lines left out)" % (len(lines) - limit)] + lines[-tail:]


def main():
    path = sys.argv[1]
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 60
    try:
        archive = tarfile.open(path)
    except (OSError, tarfile.TarError) as e:
        print("junit-failures: cannot read %s: %s" % (path, e))
        return 1
    with archive:
        for member in archive:
            name = member.name.rsplit("/", 1)[-1]
            if not (name.startswith("junit") and name.endswith(".xml")):
                continue
            try:
                root = ET.parse(archive.extractfile(member)).getroot()
            except ET.ParseError as e:
                print("junit-failures: %s: %s" % (member.name, e))
                continue
            for case in root.iter("testcase"):
                bad = case.find("failure")
                if bad is None:
                    bad = case.find("error")
                if bad is None:
                    continue
                print("== FAILED: %s (%s s)" % (case.get("name"), case.get("time")))
                if bad.get("message"):
                    print("   message: %s" % bad.get("message"))
                for line in clip(bad.text, limit):
                    print("   " + line)
                err = case.find("system-err")
                if err is not None and err.text and err.text.strip():
                    print("   -- system-err (last 30 lines)")
                    for line in err.text.strip().splitlines()[-30:]:
                        print("   " + line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
