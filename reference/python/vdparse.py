"""Read the files gdx2veda writes (.vd, .vde, .vds) into records. Standard library only.

M1.6 (James, 27 Nov 2026, m16-q3): TIMES.jl's .vd file is compared with GAMS's as parsed
values at 1e-6, not as text. This module does the parsing; the layout below is the one
gdx2veda 54.6.1 wrote for TIMES_Demo demo12 with times2veda.vdd of TIMES v4.9.8 (reference
harness 0.3.10, ``vd/`` of a reference).

A .vd file starts with header lines, ``*`` first, each ``<key>- <value>``::

    *  GDX2VEDAversion- 2005-10-07
    *         ImportID- Scenario:<run name>
    *       VEDAFlavor- TIMES
    *       Dimensions- Attribute;Commodity;Process;Period;Region;Vintage;TimeSlice;UserConstraint;PV
    * ParentDimensions- Commodity: Region; Process: Region; UserConstraint: Region
    *      SetsAllowed- Commodity;Process;UserConstraint
    *        FieldSize- Attribute:63;Commodity:63;...;PV:20
    *       NotIndexed- PV
    *         ValueDim- PV
    *  DefaultValueDim- PV
    *   FieldSeparator- ,
    *        TextDelim- "

then an empty line and one record per line: a label for each dimension but the value
dimension, in the order of ``Dimensions``, each between text delimiters (``-`` where the
attribute has no such index), and the value, a plain or exponent number::

    "VAR_Act","-","AOTETOT","2005","REG1","2005","ANNUAL","-",564.8409
    "VAR_NcapM","-","CSHNCOA1","2015","REG2","-","-","-",4.19918093197414E-14

The dimensions, the value dimension, the separator and the delimiter are read from the
header, not assumed. .vde (descriptions) and .vds (set memberships) have no header: four
delimited fields per line, read here with the .vd file's defaults (``,`` and ``"``)::

    .vde   "Attribute","-","VAR_act","Process Activity"      dimension, region or -, element, description
    .vds   "Commodity","REG1","ELC+","AGRELC"                dimension, region, set, element
"""

from __future__ import annotations

import csv
from dataclasses import dataclass, field
from pathlib import Path

ATTRIBUTE = "Attribute"


class VdError(ValueError):
    pass


@dataclass
class VdFile:
    """A parsed .vd file. ``records``: one (attribute, index, value) per line, in file order;
    ``index`` holds the labels of ``index_dims`` (the dimensions but Attribute and the value one)."""

    header: dict = field(default_factory=dict)
    dimensions: list = field(default_factory=list)
    value_dim: str = ""
    index_dims: list = field(default_factory=list)
    records: list = field(default_factory=list)

    def values(self) -> dict:
        """{(attribute, *index): value}; a key that comes twice is an error."""
        out = {}
        for attr, index, value in self.records:
            key = (attr, *index)
            if key in out:
                raise VdError(f"record {key} comes twice")
            out[key] = value
        return out

    def attributes(self) -> dict:
        """{attribute: number of records}, in the order of first appearance."""
        out = {}
        for attr, _, _ in self.records:
            out[attr] = out.get(attr, 0) + 1
        return out


def parse_header(lines) -> dict:
    """The ``*`` lines of a .vd file as {key: value}; a line without ``- `` is skipped."""
    header = {}
    for ln in lines:
        if not ln.startswith("*"):
            continue
        key, sep, value = ln[1:].rstrip("\r\n").partition("- ")
        if sep:
            header[key.strip()] = value.strip()
    return header


def parse_vd(text: str) -> VdFile:
    """Parse the text of a .vd file (layout in the module docstring)."""
    lines = text.splitlines()
    header = parse_header(lines)
    for key in ("Dimensions", "ValueDim", "FieldSeparator", "TextDelim"):
        if not header.get(key):
            raise VdError(f"no {key} line in the header")
    dims = [d.strip() for d in header["Dimensions"].split(";")]
    value_dim = header["ValueDim"]
    if dims[0] != ATTRIBUTE or dims[-1] != value_dim or dims.count(value_dim) != 1:
        raise VdError(f"expected Dimensions to start with {ATTRIBUTE} and end with the value dimension "
                      f"{value_dim}, not {dims}")
    vd = VdFile(header=header, dimensions=dims, value_dim=value_dim, index_dims=dims[1:-1])
    data = [(n, ln) for n, ln in enumerate(lines, start=1) if ln.strip() and not ln.startswith("*")]
    rows = csv.reader((ln for _, ln in data), delimiter=header["FieldSeparator"], quotechar=header["TextDelim"])
    for (n, _), row in zip(data, rows):
        if len(row) != len(dims):
            raise VdError(f"line {n}: {len(row)} fields, expected {len(dims)}")
        try:
            value = float(row[-1])
        except ValueError:
            raise VdError(f"line {n}: value '{row[-1]}' is not a number") from None
        vd.records.append((row[0], tuple(row[1:-1]), value))
    return vd


def read_vd(path) -> VdFile:
    return parse_vd(Path(path).read_text(errors="replace"))


def read_rows(path, fields: int = 4, delimiter: str = ",", quotechar: str = '"') -> list:
    """The lines of a .vde or .vds file as tuples of ``fields`` strings."""
    out = []
    with open(path, newline="", errors="replace") as f:
        for n, row in enumerate(csv.reader(f, delimiter=delimiter, quotechar=quotechar), start=1):
            if not row:
                continue
            if len(row) != fields:
                raise VdError(f"{path}, line {n}: {len(row)} fields, expected {fields}")
            out.append(tuple(row))
    return out


def main(argv=None) -> int:
    import argparse

    p = argparse.ArgumentParser(description="List the attributes of a .vd file and their record counts")
    p.add_argument("vd", type=Path)
    a = p.parse_args(argv)
    vd = read_vd(a.vd)
    print(f"{a.vd}: {len(vd.records)} records; index: {', '.join(vd.index_dims)}; value: {vd.value_dim}")
    for attr, n in vd.attributes().items():
        print(f"  {attr:<16}{n}")
    return 0


if __name__ == "__main__":
    import sys

    sys.exit(main())
