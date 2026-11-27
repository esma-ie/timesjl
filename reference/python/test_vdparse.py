"""vdparse.py on a small .vd file (harness 0.3.10, M1.6). No GAMS needed.

SAMPLE is hand-written in the layout gdx2veda 54.6.1 wrote for TIMES_Demo demo12 (CC BY 4.0) with
times2veda.vdd of TIMES v4.9.8 on 27 Nov 2026: its header lines as they were, but for the run name,
and a few of its records, one of each shape seen there (an index of labels and ``-``, a value with
and without decimals, a value with an exponent).
"""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from vdparse import VdError, parse_vd, read_rows, read_vd  # noqa: E402

SAMPLE = """\
*  GDX2VEDAversion- 2005-10-07
*         ImportID- Scenario:sample
*       VEDAFlavor- TIMES
*       Dimensions- Attribute;Commodity;Process;Period;Region;Vintage;TimeSlice;UserConstraint;PV
* ParentDimensions- Commodity: Region; Process: Region; UserConstraint: Region
*      SetsAllowed- Commodity;Process;UserConstraint
*        FieldSize- Attribute:63;Commodity:63;Process:63;Period:63;Region:63;Vintage:63;TimeSlice:63;UserConstraint:63;PV:20
*       NotIndexed- PV
*         ValueDim- PV
*  DefaultValueDim- PV
*   FieldSeparator- ,
*        TextDelim- "

"VAR_Act","-","AOTETOT","2005","REG1","2005","ANNUAL","-",564.8409
"VAR_Act","-","COTEBIO","2005","REG1","2005","ANNUAL","-",3.939
"VAR_NcapM","-","CSHNCOA1","2015","REG2","-","-","-",4.19918093197414E-14
"VAR_FOut","AGRCO2","AOTETOT","2005","REG1","2005","SD","-",4313.99647248288
"EQ_CombalM","GAS","-","2005","REG1","-","ANNUAL","-",4.5
"Cap_New","-","AOTETOT","2005","REG1","2005","-","INSTCAP",982.93885661392
"User_con","-","-","NONE","NONE","-","NONE","SOLVE_STATUS",1
"""

VDE = '"Attribute","-","VAR_act","Process Activity"\n"Attribute","-","User_ConFXM","Marginal cost of user constraint (or group-wise market share)"\n'
VDS = '"Commodity","REG1","ELC+","ELC"\n"Commodity","REG2","ELC+","AGRELC"\n'


class VdParse(unittest.TestCase):
    def test_header(self):
        vd = parse_vd(SAMPLE)
        self.assertEqual(vd.header["ImportID"], "Scenario:sample")
        self.assertEqual(vd.header["FieldSeparator"], ",")
        self.assertEqual(vd.header["TextDelim"], '"')
        self.assertEqual(vd.value_dim, "PV")
        self.assertEqual(vd.dimensions[0], "Attribute")
        self.assertEqual(vd.index_dims, ["Commodity", "Process", "Period", "Region", "Vintage", "TimeSlice",
                                         "UserConstraint"])

    def test_records(self):
        vd = parse_vd(SAMPLE)
        self.assertEqual(len(vd.records), 7)
        self.assertEqual(vd.records[0], ("VAR_Act", ("-", "AOTETOT", "2005", "REG1", "2005", "ANNUAL", "-"), 564.8409))
        self.assertEqual(vd.records[2][2], 4.19918093197414e-14)
        self.assertEqual(vd.records[6], ("User_con", ("-", "-", "NONE", "NONE", "-", "NONE", "SOLVE_STATUS"), 1.0))
        self.assertEqual(vd.attributes(), {"VAR_Act": 2, "VAR_NcapM": 1, "VAR_FOut": 1, "EQ_CombalM": 1, "Cap_New": 1,
                                           "User_con": 1})
        values = vd.values()
        self.assertEqual(len(values), 7)
        self.assertEqual(values[("EQ_CombalM", "GAS", "-", "2005", "REG1", "-", "ANNUAL", "-")], 4.5)

    def test_separator_and_delimiter_come_from_the_header(self):
        other = SAMPLE.replace("FieldSeparator- ,", "FieldSeparator- ;").replace("TextDelim- \"", "TextDelim- '")
        head, _, body = other.partition("\n\n")
        other = head + "\n\n" + body.replace('"', "'").replace(",", ";")
        self.assertEqual(parse_vd(other).records, parse_vd(SAMPLE).records)

    def test_a_label_may_hold_the_separator(self):
        vd = parse_vd(SAMPLE + '"VAR_Act","-","A,B","2005","REG1","2005","ANNUAL","-",2\n')
        self.assertEqual(vd.records[-1][1][1], "A,B")

    def test_errors(self):
        with self.assertRaises(VdError):       # no header
            parse_vd('"VAR_Act","-","AOTETOT","2005","REG1","2005","ANNUAL","-",564.8409\n')
        with self.assertRaises(VdError):       # a field too few
            parse_vd(SAMPLE + '"VAR_Act","-","AOTETOT","2005","REG1","2005","ANNUAL",1\n')
        with self.assertRaises(VdError):       # a value that is no number
            parse_vd(SAMPLE + '"VAR_Act","-","AOTETOT","2010","REG1","2005","ANNUAL","-",abc\n')
        with self.assertRaises(VdError):       # the value dimension is not the last one
            parse_vd(SAMPLE.replace("ValueDim- PV", "ValueDim- Region", 1))
        twice = parse_vd(SAMPLE + '"VAR_Act","-","AOTETOT","2005","REG1","2005","ANNUAL","-",1\n')
        with self.assertRaises(VdError):       # the same key twice
            twice.values()

    def test_files(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            (d / "s.vd").write_text(SAMPLE)
            (d / "s.vde").write_text(VDE)
            (d / "s.vds").write_text(VDS)
            self.assertEqual(len(read_vd(d / "s.vd").records), 7)
            self.assertEqual(read_rows(d / "s.vde")[0], ("Attribute", "-", "VAR_act", "Process Activity"))
            self.assertEqual(read_rows(d / "s.vds"), [("Commodity", "REG1", "ELC+", "ELC"),
                                                      ("Commodity", "REG2", "ELC+", "AGRELC")])
            (d / "bad.vds").write_text('"Commodity","REG1","ELC+"\n')
            with self.assertRaises(VdError):
                read_rows(d / "bad.vds")


if __name__ == "__main__":
    unittest.main()
