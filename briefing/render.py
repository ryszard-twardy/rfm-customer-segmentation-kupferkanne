"""Render the executive deck and the decision report from briefing/values.json and check them.

Run from the repository root:

    uv run python briefing/render.py            # both documents
    uv run python briefing/render.py --deck     # the executive deck only
    uv run python briefing/render.py --report   # the decision report only

Each document is a Jinja2 template filled from values.json, the palette in notebooks/_brand.yml
and meta.yml. Its HTML goes to briefing/build/ and Playwright Chromium prints it to PDF: the deck
as twelve 1920 x 1080 px slides, the report as six A4 pages. checks.py then checks the templates,
fonts, page fit, colour contrast and the palette's text colours, the PDF and its text layer,
figure parity with values.json (including a second render with every value moved), the deck's
word budget and speaker notes, and determinism. Any failure exits non-zero with the list.
"""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import math
import pathlib
import re
import sys

import jinja2
import yaml
from playwright.sync_api import sync_playwright

import checks

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent
TEMPLATES = HERE / "templates"
BUILD = HERE / "build"
VALUES = HERE / "values.json"
META = HERE / "meta.yml"
BRAND = REPO / "notebooks" / "_brand.yml"


# --- Documents -------------------------------------------------------------------------

@dataclasses.dataclass(frozen=True)
class Document:
    """What the render and the checks need to know about one document."""
    name: str                          # CLI flag and build file stem
    unit: str                          # what one printed page is called in messages
    template: str                      # under templates/; extends base.html.j2
    stylesheet: str                    # the document's styles, included by base.html.j2
    template_files: tuple[str, ...]    # globs under templates/ read by the template lint
    title: str                         # HTML <title> and PDF Title
    pdf_name: str
    page_tag: str                      # each page is one <page_tag id="..."> child of <body>
    pages: tuple[str, ...]             # page ids in document order
    viewport: dict
    page_px: tuple[float, float]       # page box in CSS px
    page_px_tolerance: float
    page_pt: tuple[float, float]       # PDF page in pt
    page_pt_tolerance: float
    flow_limit: float                  # bottom padding edge: flow content ends above it
    flow_allowance: dict[str, float]   # per page id, a later end accepted in the layout
    word_limits: dict[str, int]        # per page id; pages without a limit are reported only
    main_pages: int                    # the first pages, counted against main_word_limit
    main_word_limit: int | None
    lint_non_data: re.Pattern          # template text that may carry digits
    non_data_text: tuple               # (pattern, replacement) removed before the figure checks
    constants: dict[str, dict[str, int]]  # per page id, layout figures beyond the page number
    labels: frozenset[str]             # labels with a digit that the text may carry
    notes: pathlib.Path | None         # speaker notes, one section per page
    faces: tuple[str, ...] = ("300", "400", "700", "900")  # Lato weights in fonts.css

    @property
    def html(self) -> pathlib.Path:
        return BUILD / f"{self.name}.html"

    @property
    def pdf(self) -> pathlib.Path:
        return BUILD / self.pdf_name

    @property
    def page_selector(self) -> str:
        return f"body > {self.page_tag}"


STAGES = (re.compile(r"\b[Ss]tage [12]\b"), " ")
PER_1000 = (re.compile(r"\b(per\s+€|per\s+|[Mm]ultiplied\s+by\s+)1,000\b"), r"\1")
APPENDIX_LABELS = frozenset({"A1", "A2", "A3", "A4"})

# Slide templates in deck order; the first eight are the main slides, the rest the appendix.
SLIDES = ("cover", "summary", "pool", "margin", "cause", "modelled", "pilot", "ask",
          "a1", "a2", "a3", "a4")
DECK = Document(
    name="deck",
    unit="slide",
    template="deck.html.j2",
    stylesheet="deck.css",
    template_files=("base.html.j2", "fonts.css", "deck.css", "deck.html.j2", "slides/*"),
    title="Kupferkanne: win-back discount allocation – executive deck",
    pdf_name="kupferkanne_win_back_discount_allocation_deck.pdf",
    page_tag="section",
    pages=SLIDES,
    viewport={"width": 1920, "height": 1080},
    page_px=(1920, 1080),
    page_px_tolerance=0,
    page_pt=(1440.0, 810.0),  # 1920 x 1080 px at 0.75 pt per px
    page_pt_tolerance=0.01,
    flow_limit=920,
    flow_allowance={"a1": 924},  # A1 is fitted as in the accepted layout and ends at y 923.8
    # Word budget: whitespace-separated tokens of each slide's rendered text; the appendix
    # slides are reported only.
    word_limits={"cover": 60, "summary": 90, "pool": 75, "margin": 75, "cause": 75,
                 "modelled": 75, "pilot": 75, "ask": 75},
    main_pages=8,
    main_word_limit=600,
    # Appendix names, pilot stages, the A2 total row and the unit of the per-1,000 figures.
    lint_non_data=re.compile(
        r"Appendix A[1-4]|Stage [12]|100\.00%|per (?:€1,000|1,000 euros)|[Mm]ultiplied by 1,000"),
    non_data_text=(STAGES, PER_1000),
    constants={"a2": {"100.00%": 2}},  # the A2 total row
    labels=APPENDIX_LABELS,
    notes=HERE / "speaker_notes.md",
)

MM = 96 / 25.4  # CSS px per mm
PT_PER_MM = 72 / 25.4
EACH_1000 = (re.compile(r"\b(each\s+€)1,000\b"), r"\1")
EXHIBITS = (re.compile(r"\bExhibits? [1-6](?: and [1-6])?\b"), " ")
# Page templates in report order: cover and summary, situation and problem, cause and
# uncertainty, pilot and ask, appendix A1 and A2, appendix A3, A4 and the sources.
REPORT_PAGES = ("cover", "situation", "cause", "pilot", "appendix-1", "appendix-2")
REPORT = Document(
    name="report",
    unit="page",
    template="report.html.j2",
    stylesheet="report.css",
    template_files=("base.html.j2", "fonts.css", "report.css", "report.html.j2", "pages/*"),
    title="Kupferkanne: win-back discount allocation – decision report",
    pdf_name="kupferkanne_win_back_discount_allocation_report.pdf",
    page_tag="article",
    pages=REPORT_PAGES,
    viewport={"width": 794, "height": 1123},
    page_px=(210 * MM, 297 * MM),
    page_px_tolerance=0.1,
    page_pt=(210 * PT_PER_MM, 297 * PT_PER_MM),
    page_pt_tolerance=0.5,
    flow_limit=277 * MM,  # the bottom padding edge of each page: 297 mm less 20 mm
    flow_allowance={},
    word_limits={},  # words per page are reported only
    main_pages=0,
    main_word_limit=None,
    # Exhibit numbers, appendix labels, pilot stages, the A2 total row and the unit of the
    # per-1,000 figures.
    lint_non_data=re.compile(r"Exhibits? [1-6](?: and [1-6])?|\bA[1-4]\b|Stage [12]|100\.00%"
                             r"|(?:per|each) €1,000|[Mm]ultiplied by 1,000"),
    non_data_text=(STAGES, PER_1000, EACH_1000, EXHIBITS),
    constants={"appendix-1": {"100.00%": 2}},  # the A2 total row
    labels=APPENDIX_LABELS,
    notes=None,
)
DOCUMENTS = (DECK, REPORT)

NUMBER_WORDS = ("zero", "one", "two", "three", "four", "five", "six",
                "seven", "eight", "nine", "ten", "eleven", "twelve")


# --- Number formats --------------------------------------------------------------------

def num(value: float, dp: int) -> str:
    """Comma thousands and fixed decimals: num(8476200.74, 2) -> '8,476,200.74'."""
    return f"{value:,.{dp}f}"


def pct(value: float, dp: int) -> str:
    """pct(26.117, 1) -> '26.1%'."""
    return num(value, dp) + "%"


def eur(value: float, dp: int) -> str:
    """Euro sign before the number, no space: eur(2464.74, 0) -> '€2,465'."""
    return ("-" if value < 0 else "") + "€" + num(abs(value), dp)


def times(value: float, dp: int) -> str:
    """times(1.8469, 2) -> '1.85×'."""
    return num(value, dp) + "×"


def spell(value: float) -> str:
    """Small whole numbers as words: spell(10) -> 'ten'."""
    n = int(value)
    if n != value or not 0 <= n < len(NUMBER_WORDS):
        raise ValueError(f"spell() takes a whole number from 0 to 12, got {value!r}")
    return NUMBER_WORDS[n]


def px(value: float) -> int:
    """Round a computed length to whole pixels, halves up."""
    return math.floor(value + 0.5)


def linear(value: float, d0: float, d1: float, r0: float, r1: float) -> float:
    """Map value from the domain d0..d1 onto the range r0..r1."""
    return r0 + (value - d0) / (d1 - d0) * (r1 - r0)


def split_track(shares: list[float], width: int) -> list[int]:
    """Split a `width`-unit track by shares with largest-remainder rounding, so the parts sum
    to `width`."""
    total = sum(shares)
    exact = [share / total * width for share in shares]
    parts = [math.floor(x) for x in exact]
    for i in sorted(range(len(exact)), key=lambda i: parts[i] - exact[i])[: width - sum(parts)]:
        parts[i] += 1
    if sum(parts) != width:
        raise ValueError(f"track parts sum to {sum(parts)}, not {width}")
    return parts


# --- Inputs ----------------------------------------------------------------------------

def collapse(node: object) -> object:
    """Replace every values.json leaf ({class, unit, value, ...}) by its value."""
    if checks.is_leaf(node):
        return node["value"]
    if isinstance(node, dict):
        return {key: collapse(child) for key, child in node.items()}
    return node


def load_inputs() -> dict:
    raw = json.loads(VALUES.read_text(encoding="utf-8"))
    color = yaml.safe_load(BRAND.read_text(encoding="utf-8"))["color"]
    palette = dict(color["palette"], foreground=color["foreground"],
                   background=color["background"])
    meta = yaml.safe_load(META.read_text(encoding="utf-8"))
    return {
        "raw": raw,
        "v": collapse(raw),
        "palette": {name.replace("_", "-"): hex_value for name, hex_value in palette.items()},
        "meta": {"date": str(meta["date"]), "status": meta.get("status") or ""},
    }


def render_html(doc: Document, inputs: dict) -> str:
    env = jinja2.Environment(
        loader=jinja2.FileSystemLoader(TEMPLATES),
        undefined=jinja2.StrictUndefined,
        autoescape=True,
        trim_blocks=True,
        lstrip_blocks=True,
        keep_trailing_newline=True,
    )
    env.filters.update(num=num, pct=pct, eur=eur, times=times, spell=spell, px=px)
    env.globals.update(split_track=split_track, linear=linear)
    return env.get_template(doc.template).render(
        v=inputs["v"], palette=inputs["palette"], meta=inputs["meta"], pages=doc.pages,
        stylesheet=doc.stylesheet)


# --- Browser pass ----------------------------------------------------------------------

def browser_pass(playwright, doc: Document, html_path: pathlib.Path,
                 pdf_path: pathlib.Path) -> dict:
    browser = playwright.chromium.launch()
    try:
        page = browser.new_page(viewport=doc.viewport)
        page.goto(html_path.as_uri())
        page.evaluate("() => document.fonts.ready.then(() => true)")
        pages = page.evaluate(checks.JS_PAGES, doc.page_selector)
        shots = {s["id"]: hashlib.sha256(
            page.locator(f"{doc.page_tag}#{s['id']}").screenshot()).hexdigest() for s in pages}
        result = {"faces": page.evaluate(checks.JS_FACES), "pages": pages, "shots": shots,
                  "runs": page.evaluate(checks.JS_TEXT_COLOURS, doc.page_selector),
                  "fallbacks": checks.font_fallbacks(doc, page)}
        page.pdf(path=str(pdf_path), prefer_css_page_size=True, print_background=True)
        return result
    finally:
        browser.close()


# --- Build -----------------------------------------------------------------------------

def build(doc: Document) -> list[str]:
    """Render, print and check one document; print its page summary; return the failures."""
    inputs = load_inputs()
    BUILD.mkdir(exist_ok=True)
    fails = checks.lint_templates(doc, TEMPLATES)
    html_text = render_html(doc, inputs)
    doc.html.write_bytes(html_text.encode("utf-8"))
    second_html = BUILD / f"{doc.name}.second.html"
    second_html.write_bytes(render_html(doc, inputs).encode("utf-8"))
    second_pdf = BUILD / f"{doc.name}.second.pdf"
    with sync_playwright() as playwright:
        first = browser_pass(playwright, doc, doc.html, doc.pdf)
        second = browser_pass(playwright, doc, second_html, second_pdf)
    pdf_fails, texts = checks.check_pdf(doc, doc.pdf)
    _, second_texts = checks.check_pdf(doc, second_pdf)
    first.update(html=doc.html.read_bytes(), texts=texts)
    second.update(html=second_html.read_bytes(), texts=second_texts)
    second_html.unlink()
    second_pdf.unlink()

    pages = first["pages"]
    counts = checks.word_counts(pages)
    dom_texts = [s["text"] for s in pages]
    date = inputs["meta"]["date"]
    raw = inputs["raw"]
    notes = None
    if doc.notes is not None:
        notes = doc.notes.read_text(encoding="utf-8") if doc.notes.exists() else ""
    if [s["id"] for s in pages] != list(doc.pages):
        fails.append(f"{doc.unit}s in the {doc.name} {[s['id'] for s in pages]} "
                     f"are not {list(doc.pages)}")
    fails += checks.check_faces(doc, first["faces"]) + first["fallbacks"]
    fails += checks.check_fit(doc, pages)
    fails += checks.check_contrast(doc, first["runs"])
    fails += checks.check_palette(doc, inputs["palette"])
    fails += pdf_fails + checks.check_text_layer(doc, texts)
    fails += checks.check_text_layer(doc, dom_texts, doc.unit)
    fails += checks.check_pdf_matches_html(doc, texts, pages)
    fails += checks.check_parity(doc, raw, [(s["id"], t) for s, t in zip(pages, texts)],
                                 None if notes is None else checks.split_notes(notes)[1], date)
    fails += checks.check_parity(doc, raw, [(s["id"], s["text"]) for s in pages], None, date,
                                 doc.unit)
    moved_html = render_html(doc, dict(inputs, v=checks.perturb(raw)))
    fails += checks.check_sentinel(doc, raw, date, html_text, moved_html)
    fails += checks.check_words(doc, counts)
    if notes is not None:
        fails += checks.check_notes(doc, notes, pages) + checks.check_notes_text(doc, notes)
    fails += checks.check_determinism(doc, first, second)

    width = max(len(sid) for sid in doc.pages)
    print(f"{'page':>4}  {doc.unit:{width}} {'words':>5}  {'lowest y':>8}  "
          f"(content area ends at y {doc.flow_limit:g})")
    for number, s in enumerate(pages, 1):
        over = s["lowest"] - doc.flow_limit
        note = f"  over by {over:.1f}" if over > 0 else ""
        print(f"{number:>4}  {s['id']:{width}} {counts[s['id']]:>5}  {s['lowest']:>8.1f}{note}")
    main = ""
    if doc.main_word_limit is not None:
        main_words = sum(list(counts.values())[:doc.main_pages])
        main = f"main {doc.unit}s: {main_words} words; "
    print(f"{main}PDF {doc.pdf.relative_to(REPO).as_posix()}: {len(texts)} pages, "
          f"{doc.pdf.stat().st_size:,} B")
    (BUILD / f"{doc.name}_checks.json").write_text(json.dumps(
        {"words": counts, "lowest": {s["id"]: s["lowest"] for s in pages},
         "shots": first["shots"], "failures": fails}, indent=1), encoding="utf-8")
    return fails


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=(
        "Render the executive deck and the decision report to PDF and check them "
        "(no flag: both)."))
    which = parser.add_mutually_exclusive_group()
    for doc in DOCUMENTS:
        which.add_argument(f"--{doc.name}", action="store_true",
                           help=f"render and check the {doc.title.rsplit(' – ', 1)[1]} only")
    args = parser.parse_args(argv)
    docs = [doc for doc in DOCUMENTS if getattr(args, doc.name)] or list(DOCUMENTS)
    failed = 0
    for doc in docs:
        fails = build(doc)
        if fails:
            failed += 1
            print(f"\n{doc.name}: {len(fails)} check(s) failed:")
            for fail in fails:
                print(f"  - {fail}")
        else:
            print(f"{doc.name}: all checks passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
