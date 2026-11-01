"""Unit tests for egress_allowlist.py; run with: python3 -m unittest discover -s build_files/claude-vm"""

import json
import tempfile
import unittest
from pathlib import Path

import egress_allowlist as ea

HERE = Path(__file__).resolve().parent
SETTINGS = {"permissions": {"x": 1}, "sandbox": {"enabled": True, "filesystem": {"allowWrite": ["~/a"]}}}


def problems(text):
    return ea.validate(ea.parse(text))


class ParseTest(unittest.TestCase):
    def test_comments_blanks_and_whitespace(self):
        text = "# header\n\n  github.com  # trailing\n\t\nquay.io\n"
        self.assertEqual(ea.parse(text), [(3, "github.com"), (5, "quay.io")])


class ValidateTest(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(problems("github.com\nfiles.pythonhosted.org\nx-y.example.co.uk\n"), [])

    def test_each_invalid_form_is_rejected(self):
        for bad in ["*.github.com", "GitHub.com", "1.2.3.4", "github.com:443", "github.com/x", "localhost",
                    "-a.com", "a-.com", "a..com", ".github.com", "git hub.com", "a_b.com", "a" * 64 + ".com",
                    ("a" * 60 + ".") * 5 + "com"]:
            with self.subTest(bad=bad):
                self.assertEqual(len(problems(bad)), 1, problems(bad))
                self.assertIn("invalid entry", problems(bad)[0])

    def test_empty(self):
        self.assertEqual(problems("# only a comment\n\n"), ["empty allowlist"])

    def test_duplicate_names_both_lines(self):
        self.assertEqual(problems("github.com\nquay.io\ngithub.com\n"), ["line 3: duplicate of line 1 ('github.com')"])

    def test_redundant_subdomain_names_the_parent(self):
        self.assertEqual(
            problems("api.github.com\ngithub.com\n"),
            ["line 1: 'api.github.com' is already covered by 'github.com' (line 2)"],
        )

    def test_deep_redundancy_and_unrelated_suffix(self):
        self.assertEqual(len(problems("a.b.example.com\nexample.com\n")), 1)
        self.assertEqual(problems("evilgithub.com\ngithub.com\n"), [])  # not a subdomain
        self.assertEqual(problems("github.com.evil.org\ngithub.com\n"), [])

    def test_all_problems_are_reported_at_once(self):
        self.assertEqual(len(problems("A.com\nb.com\nb.com\n*.c.com\n")), 3)


class BuildTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.list = self.dir / "list.txt"
        self.settings = self.dir / "settings.json"
        self.settings.write_text(json.dumps(SETTINGS))
        self.out = self.dir / "out" / "egress"

    def run_main(self, text):
        self.list.write_text(text)
        return ea.main([str(self.list), str(self.settings), str(self.out)])

    def test_outputs(self):
        self.assertEqual(self.run_main("quay.io\ngithub.com\n"), 0)
        self.assertEqual((self.out / "allowlist.txt").read_text(), "github.com\nquay.io\n")
        self.assertEqual((self.out / "nginx-allow.map").read_text(), ".github.com  1;\n.quay.io  1;\n")
        self.assertEqual(
            (self.out / "dnsmasq-servers").read_text(),
            "server=/github.com/127.0.0.53\nserver=/quay.io/127.0.0.53\n",
        )

    def test_settings_merge_keeps_other_keys(self):
        self.assertEqual(self.run_main("quay.io\ngithub.com\n"), 0)
        merged = json.loads(self.settings.read_text())
        self.assertEqual(
            merged["sandbox"]["network"]["allowedDomains"],
            ["github.com", "*.github.com", "quay.io", "*.quay.io"],
        )
        self.assertEqual(merged["permissions"], SETTINGS["permissions"])
        self.assertEqual(merged["sandbox"]["filesystem"], SETTINGS["sandbox"]["filesystem"])
        self.assertTrue(merged["sandbox"]["enabled"])
        self.assertTrue(self.settings.read_text().endswith("}\n"))

    def test_existing_network_keys_survive_and_list_is_replaced(self):
        self.settings.write_text(json.dumps({"sandbox": {"network": {"allowedDomains": ["old.com"], "x": 1}}}))
        self.assertEqual(self.run_main("github.com\n"), 0)
        network = json.loads(self.settings.read_text())["sandbox"]["network"]
        self.assertEqual(network, {"allowedDomains": ["github.com", "*.github.com"], "x": 1})

    def test_idempotent(self):
        self.assertEqual(self.run_main("github.com\n"), 0)
        first = self.settings.read_text()
        self.assertEqual(self.run_main("github.com\n"), 0)
        self.assertEqual(self.settings.read_text(), first)

    def test_invalid_list_writes_nothing(self):
        before = self.settings.read_text()
        self.assertEqual(self.run_main("*.github.com\n"), 1)
        self.assertEqual(self.settings.read_text(), before)
        self.assertFalse(self.out.exists())

    def test_usage_error(self):
        with self.assertRaises(SystemExit) as raised:
            ea.main([])
        self.assertEqual(raised.exception.code, 2)


class RepoFilesTest(unittest.TestCase):
    def test_the_shipped_allowlist_is_valid(self):
        entries = ea.parse((HERE / "egress-allowlist.txt").read_text())
        self.assertEqual(ea.validate(entries), [])
        domains = {d for _, d in entries}
        self.assertTrue({"github.com", "anthropic.com", "quay.io"} <= domains)
        self.assertNotIn("example.com", domains)


if __name__ == "__main__":
    unittest.main()
