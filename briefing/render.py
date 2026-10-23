"""Render the executive deck from briefing/values.json and check every page.

Run from the repository root:

    uv run python briefing/render.py --deck

Writes briefing/build/deck.html and prints it to the deck PDF with Playwright
Chromium, then checks the templates, fonts, page fit, the PDF and its text
layer, figure parity with values.json (including a second render with every
value moved), the word budget, the speaker notes and determinism. Any failure exits non-zero with the list. `--report` is reserved
for the written report, which has no template yet.
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import html
import json
import math
import pathlib
import re
import sys
import unicodedata

import jinja2
import yaml
from playwright.sync_api import sync_playwright
from pypdf import PdfReader

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent
TEMPLATES = HERE / "templates"
BUILD = HERE / "build"
VALUES = HERE / "values.json"
META = HERE / "meta.yml"
NOTES = HERE / "speaker_notes.md"
BRAND = REPO / "notebooks" / "_brand.yml"

DECK_HTML = BUILD / "deck.html"
DECK_PDF = BUILD / "kupferkanne_win_back_discount_allocation_deck.pdf"
DECK_TITLE = "Kupferkanne: win-back discount allocation – executive deck"
# Slide templates in deck order; the first eight are the main slides, the rest the appendix.
SLIDES = ("cover", "summary", "pool", "margin", "cause", "modelled", "pilot", "ask", "a1", "a2", "a3", "a4")
MAIN_SLIDES = 8
DECK_PAGES = len(SLIDES)
PAGE_PT = (1440.0, 810.0)  # 1920 x 1080 px at 0.75 pt per px
FLOW_LIMIT_Y = 920  # bottom padding edge: flow content ends above it
FLOW_ALLOWANCE = {"a1": 924}  # A1 is fitted as in the accepted layout and ends at y 923.8
DECK_FACES = ("300", "400", "700", "900")

# Word budget: whitespace-separated tokens of each slide's rendered text.
WORD_LIMITS = {"cover": 60, "summary": 90}
CONTENT_WORD_LIMIT = 75  # each main slide after the summary; appendix slides are reported only
MAIN_WORD_LIMIT = 600

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
    """Split a `width`-px track by shares with largest-remainder rounding, so the parts sum to `width`."""
    total = sum(shares)
    exact = [share / total * width for share in shares]
    parts = [math.floor(x) for x in exact]
    for i in sorted(range(len(exact)), key=lambda i: parts[i] - exact[i])[: width - sum(parts)]:
        parts[i] += 1
    if sum(parts) != width:
        raise ValueError(f"track parts sum to {sum(parts)}, not {width}")
    return parts


# --- Inputs ----------------------------------------------------------------------------

def is_leaf(node: object) -> bool:
    return isinstance(node, dict) and "value" in node and "unit" in node


def collapse(node: object) -> object:
    """Replace every values.json leaf ({class, unit, value, ...}) by its value."""
    if is_leaf(node):
        return node["value"]
    if isinstance(node, dict):
        return {key: collapse(child) for key, child in node.items()}
    return node


def leaves(node: object, path: str = ""):
    if is_leaf(node):
        yield path, node
    elif isinstance(node, dict):
        for key, child in node.items():
            yield from leaves(child, f"{path}.{key}" if path else key)


def load_inputs() -> dict:
    raw = json.loads(VALUES.read_text(encoding="utf-8"))
    color = yaml.safe_load(BRAND.read_text(encoding="utf-8"))["color"]
    palette = dict(color["palette"], foreground=color["foreground"], background=color["background"])
    meta = yaml.safe_load(META.read_text(encoding="utf-8"))
    return {
        "raw": raw,
        "v": collapse(raw),
        "palette": {name.replace("_", "-"): hex_value for name, hex_value in palette.items()},
        "meta": {"date": str(meta["date"]), "status": meta.get("status") or ""},
    }


def render_html(inputs: dict) -> str:
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
    return env.get_template("deck.html.j2").render(
        v=inputs["v"], palette=inputs["palette"], meta=inputs["meta"], slides=SLIDES)


# --- Template lint ---------------------------------------------------------------------

JINJA = re.compile(r"\{\{.*?\}\}|\{%.*?%\}|\{#.*?#\}", re.S)
STRING_LITERAL = re.compile(r"""(["'])(.*?)\1""")
TAG = re.compile(r"<[^>]*>", re.S)
TEXT_ATTRIBUTE = re.compile(r'\b(?:aria-label|alt|title)="([^"]*)"')
ENTITY = re.compile(r"&#?\w+;")
HEX_COLOUR = re.compile(r"(?<![&\w])#[0-9A-Fa-f]{3,8}\b")
COLOUR_FUNCTION = re.compile(r"\b(?:rgba?|hsla?)\(", re.I)
# Text that may carry digits in a template: appendix names, pilot stages, the A2 total
# row and the unit constant of the per-1,000 figures.
TEMPLATE_NON_DATA = re.compile(
    r"Appendix A[1-4]|Stage [12]|100\.00%|per (?:€1,000|1,000 euros)|[Mm]ultiplied by 1,000")
# String literals that name a template, a path part or a slide id, not a figure.
TEMPLATE_NAME = re.compile(r"[a-z][a-z0-9_]*$|[\w/.-]*\.j2$")


def lint_templates() -> list[str]:
    """Colours only through var(--...); no figure typed into template text."""
    fails = []
    for path in sorted(p for p in TEMPLATES.rglob("*") if p.is_file()):
        rel = path.relative_to(TEMPLATES.parent).as_posix()
        source = path.read_text(encoding="utf-8")
        fails += [f"{rel}: colour literal {m.group(0)}" for m in HEX_COLOUR.finditer(source)]
        fails += [f"{rel}: colour function {m.group(0)}" for m in COLOUR_FUNCTION.finditer(source)]
        if path.suffix == ".css":
            continue
        texts = [lit for tag in JINJA.findall(source) for _, lit in STRING_LITERAL.findall(tag)
                 if not TEMPLATE_NAME.match(lit)]
        markup = JINJA.sub(" ", source)
        texts += TEXT_ATTRIBUTE.findall(markup)
        texts.append(TAG.sub(" ", markup))
        for text in texts:
            text = TEMPLATE_NON_DATA.sub(" ", ENTITY.sub(" ", text))
            fails += [f"{rel}: figure typed into the template: {m.group(0)!r}"
                      for m in re.finditer(r"\d[\d,.]*", text)]
    return fails


# --- Browser pass ----------------------------------------------------------------------

JS_FACES = """() => [...document.fonts].map(f => ({
  family: f.family.replace(/"/g, ''), weight: String(f.weight), style: f.style, status: f.status}))"""

JS_SLIDES = """() => [...document.querySelectorAll('body > section')].map(s => {
  const box = s.getBoundingClientRect();
  const label = s.querySelector('.label');
  const out = {id: s.id, label: label ? label.textContent : '', text: s.innerText,
               size: [box.width, box.height], outside: [], spill: [], overflow: [], lowest: 0};
  for (const el of s.querySelectorAll('*')) {
    const r = el.getBoundingClientRect();
    const name = el.tagName.toLowerCase() + ' "' + (el.textContent || '').trim().slice(0, 40) + '"';
    if ((r.width || r.height) && (r.left < box.left - 0.5 || r.top < box.top - 0.5 ||
        r.right > box.right + 0.5 || r.bottom > box.bottom + 0.5)) out.outside.push(name);
    if (el.style.width || el.style.height) {
      // A box sized in the template (a bar, a column, a chart frame) must hold its children.
      for (const child of el.children) {
        const c = child.getBoundingClientRect();
        if (c.left < r.left - 0.5 || c.top < r.top - 0.5 || c.right > r.right + 0.5 || c.bottom > r.bottom + 0.5)
          out.spill.push(name + ' > ' + child.tagName.toLowerCase() + ' "' + child.textContent.trim().slice(0, 30) + '"');
      }
    }
    const cs = getComputedStyle(el);
    const holdsText = [...el.childNodes].some(n => n.textContent.trim() &&
      (n.nodeType === 3 || (n.nodeType === 1 && getComputedStyle(n).display === 'inline')));
    if (holdsText && cs.display !== 'inline') {
      // With a line-height below the font's content area (1.2 em for Lato), glyph boxes reach
      // past the line box by half the difference; that is layout, not overflowing text.
      const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT,
        {acceptNode: n => n.textContent.trim() ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP});
      const range = document.createRange();
      range.selectNodeContents(walker.nextNode());
      const glyph = range.getClientRects()[0];
      const lineHeight = parseFloat(cs.lineHeight);
      const slack = (glyph && lineHeight ? Math.max(0, glyph.height - lineHeight) / 2 : 0) + 1;
      if (el.scrollWidth > el.clientWidth + 1 || el.scrollHeight > el.clientHeight + slack) out.overflow.push(name);
    }
    if (!el.closest('.foot')) out.lowest = Math.max(out.lowest, r.bottom - box.top);
  }
  return out;
})"""


def font_fallbacks(page) -> list[str]:
    """Every text node must be drawn with the loaded Lato web font, never a platform fallback."""
    cdp = page.context.new_cdp_session(page)
    cdp.send("DOM.enable")
    cdp.send("CSS.enable")
    root = cdp.send("DOM.getDocument", {"depth": -1})["root"]["nodeId"]
    fails = []
    for node in cdp.send("DOM.querySelectorAll", {"nodeId": root, "selector": "section *"})["nodeIds"]:
        fonts = cdp.send("CSS.getPlatformFontsForNode", {"nodeId": node})["fonts"]
        bad = [f"{f['familyName']} ({f['glyphCount']} glyphs)" for f in fonts
               if not (f["isCustomFont"] and f["familyName"].startswith("Lato"))]
        if bad:
            html_text = cdp.send("DOM.getOuterHTML", {"nodeId": node})["outerHTML"]
            fails.append(f"font fallback {', '.join(bad)} in {TAG.sub('', html_text)[:60]!r}")
    cdp.detach()
    return fails


def browser_pass(playwright, html_path: pathlib.Path, pdf_path: pathlib.Path) -> dict:
    browser = playwright.chromium.launch()
    try:
        page = browser.new_page(viewport={"width": 1920, "height": 1080})
        page.goto(html_path.as_uri())
        page.evaluate("() => document.fonts.ready.then(() => true)")
        slides = page.evaluate(JS_SLIDES)
        shots = {s["id"]: hashlib.sha256(page.locator(f"section#{s['id']}").screenshot()).hexdigest()
                 for s in slides}
        result = {"faces": page.evaluate(JS_FACES), "slides": slides, "shots": shots,
                  "fallbacks": font_fallbacks(page)}
        page.pdf(path=str(pdf_path), prefer_css_page_size=True, print_background=True)
        return result
    finally:
        browser.close()


# --- Checks ----------------------------------------------------------------------------

def check_faces(faces: list[dict]) -> list[str]:
    fails = []
    for weight in DECK_FACES:
        found = [f for f in faces if f["family"] == "Lato" and f["weight"] == weight and f["style"] == "normal"]
        if not found:
            fails.append(f"font face Lato {weight} is not declared")
        elif found[0]["status"] != "loaded":
            fails.append(f"font face Lato {weight} is {found[0]['status']}, not loaded")
    return fails


def check_fit(slides: list[dict]) -> list[str]:
    fails = []
    for s in slides:
        if s["size"] != [1920, 1080]:
            fails.append(f"{s['id']}: slide is {s['size'][0]:g} x {s['size'][1]:g} px, not 1920 x 1080")
        fails += [f"{s['id']}: box outside the slide: {name}" for name in s["outside"]]
        fails += [f"{s['id']}: child spills out of its sized box: {name}" for name in s["spill"]]
        fails += [f"{s['id']}: text overflows its box: {name}" for name in s["overflow"]]
        limit = FLOW_ALLOWANCE.get(s["id"], FLOW_LIMIT_Y)
        if s["lowest"] > limit:
            fails.append(f"{s['id']}: content ends at y {s['lowest']:.1f}, past {limit}")
    return fails


def font_objects(resources, seen=None):
    """Fonts of a page's resources, including those of nested form XObjects."""
    seen = set() if seen is None else seen
    resources = resources.get_object() if resources is not None else {}
    for ref in (resources.get("/Font") or {}).values():
        yield ref.get_object()
    for ref in (resources.get("/XObject") or {}).values():
        xobject = ref.get_object()
        if id(xobject) not in seen and xobject.get("/Subtype") == "/Form":
            seen.add(id(xobject))
            yield from font_objects(xobject.get("/Resources"), seen)


def check_pdf(path: pathlib.Path) -> tuple[list[str], list[str]]:
    reader = PdfReader(path)
    fails = []
    if len(reader.pages) != DECK_PAGES:
        fails.append(f"PDF has {len(reader.pages)} pages, not {DECK_PAGES}")
    for number, page in enumerate(reader.pages, 1):
        size = (float(page.mediabox.width), float(page.mediabox.height))
        if any(abs(a - b) > 0.01 for a, b in zip(size, PAGE_PT)):
            fails.append(f"PDF page {number} is {size[0]:g} x {size[1]:g} pt, not 1440 x 810")
        for font in font_objects(page.get("/Resources")):
            name = str(font.get("/BaseFont", font.get("/Subtype")))
            descriptor = font
            if font.get("/Subtype") == "/Type0":
                descriptor = font["/DescendantFonts"][0].get_object()
            descriptor = descriptor.get("/FontDescriptor")
            embedded = descriptor is not None and any(
                key in descriptor.get_object() for key in ("/FontFile", "/FontFile2", "/FontFile3"))
            if "Lato" not in name:
                fails.append(f"PDF page {number}: font {name} is not Lato")
            if not embedded:
                fails.append(f"PDF page {number}: font {name} is not embedded")
    title = reader.metadata.title if reader.metadata else None
    if title != DECK_TITLE:
        fails.append(f"PDF Title is {title!r}, not {DECK_TITLE!r}")
    return sorted(set(fails), key=fails.index), [page.extract_text() for page in reader.pages]


FORBIDDEN_TEXT = (
    (re.compile(r"\bpercent\b", re.I), 'the word "percent"'),
    (re.compile(r"\bEUR\b"), '"EUR"'),
    (re.compile("\u2014"), "an em dash (U+2014)"),
    (re.compile("[\u2018\u2019\u201c\u201d]"), "a curly quote"),
    (re.compile(r"\d\s?x\b"), "the letter x as a multiplier"),
)
RETIRED = re.compile(
    r"8\.53M|5\.10M|59\.78%|171\.77K|\b10[79]\b[^.\n]{0,30}\bmeasures\b|\bnine-step\b|460K"
    r"|15,000 customers|upside of acting|the pool is small", re.I)


def check_text_layer(texts: list[str], where: str = "PDF page") -> list[str]:
    """Banned forms per page. Run on the PDF text layer and on each slide's DOM text: letter-spaced
    labels can come out of the PDF as single spaced letters, which no word pattern matches."""
    fails = []
    for number, text in enumerate(texts, 1):
        for pattern, what in FORBIDDEN_TEXT:
            fails += [f"{where} {number}: {what}: {m.group(0)!r}" for m in pattern.finditer(text)]
    if not any("×" in text for text in texts):
        fails.append(f"{where} text has no × sign")
    return fails


def check_notes_text(text: str) -> list[str]:
    """The notes are read aloud, so "percent" and "times" stay; "EUR", dashes and quotes do not."""
    return [f"speaker notes: {what}: {m.group(0)!r}"
            for pattern, what in FORBIDDEN_TEXT[1:4] for m in pattern.finditer(text)]


def check_pdf_matches_html(texts: list[str], slides: list[dict]) -> list[str]:
    """Each PDF page carries the same characters as its slide's DOM text (whitespace aside)."""
    def chars(text: str) -> collections.Counter:
        return collections.Counter(c for c in unicodedata.normalize("NFKC", text) if not c.isspace())
    fails = []
    for number, (text, slide) in enumerate(zip(texts, slides), 1):
        pdf_chars, dom_chars = chars(text), chars(slide["text"])
        if pdf_chars != dom_chars:
            fails.append(f"PDF page {number} text differs from the HTML: only in PDF "
                         f"{dict(pdf_chars - dom_chars)}, only in HTML {dict(dom_chars - pdf_chars)}")
    return fails


NUMBER = re.compile(r"(?<![\w.,])(€?)(\d{1,3}(?:,\d{3})+|\d+)(\.\d+)?([%×KM]?)(?!\w)")
LABEL_WITH_DIGIT = re.compile(r"\b[A-Za-z]+\d+\b")
UNIT_WORD = re.compile(r"\s+(percent|euros|times)\b")  # how the notes say %, € and ×
UNIT_OF = {"€": "eur", "%": "pct", "×": "ratio", "euros": "eur", "percent": "pct", "times": "ratio"}


def number_forms(raw: dict) -> tuple[dict[str, set[str]], set[str]]:
    """How each leaf may print, by unit: 0 to 4 dp, with or without thousands commas;
    and the numbers inside text leaves."""
    forms, text_forms = collections.defaultdict(set), set()
    for _, leaf in leaves(raw):
        value = leaf["value"]
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            printed = {f"{value:{sep}.{dp}f}" for dp in range(5) for sep in ("", ",")}
            forms[leaf["unit"]] |= printed
            forms["any"] |= printed
        elif isinstance(value, str):
            text_forms |= {m.group(0) for m in NUMBER.finditer(value)}
    return forms, text_forms


def strip_non_data(text: str, date: str) -> str:
    text = text.replace(date, " ") if date else text
    text = re.sub(r"\b[Ss]tage [12]\b", " ", text)
    # The unit of the per-1,000 figures.
    text = re.sub(r"\b(per\s+€|per\s+|[Mm]ultiplied\s+by\s+)1,000\b", r"\1", text)
    return text


def page_constants(page: int | None, sid: str | None) -> collections.Counter:
    """Figures that are layout, not data: the page marker and the A2 total row."""
    spare = collections.Counter({str(page): 1} if page else {})
    if sid == "a2":
        spare["100.00%"] = 2
    return spare


def check_parity(raw: dict, pages: list[tuple[str, str]], notes_body: str | None, date: str,
                 where: str = "PDF page") -> list[str]:
    """pages: (slide id, text). Figures must be values.json leaves of their unit at some precision."""
    forms, text_forms = number_forms(raw)
    allowed_labels = {"A1", "A2", "A3", "A4"}
    fails = []
    sources = [(f"{where} {n} ({sid})", text, n, sid) for n, (sid, text) in enumerate(pages, 1)]
    if notes_body is not None:
        sources.append(("speaker notes", notes_body, None, None))
    for label, text, number, sid in sources:
        fails += [f"{label}: retired figure or phrase {m.group(0)!r}" for m in RETIRED.finditer(text)]
        text = strip_non_data(text, date)
        fails += [f"{label}: unexpected label {m.group(0)!r}" for m in LABEL_WITH_DIGIT.finditer(text)
                  if m.group(0) not in allowed_labels]
        spare = page_constants(number, sid)
        for m in NUMBER.finditer(text):
            sign, whole, decimals, suffix = m.groups()
            word = UNIT_WORD.match(text, m.end())
            unit = UNIT_OF.get(sign or suffix or (word.group(1) if word else ""), "any")
            if suffix not in ("K", "M") and whole + (decimals or "") in forms[unit]:
                continue
            if m.group(0) in text_forms:
                continue
            if spare[m.group(0)] > 0:
                spare[m.group(0)] -= 1
                continue
            fails.append(f"{label}: figure {m.group(0)!r} is not a values.json leaf"
                         + ("" if unit == "any" else f" with unit {unit}"))
    return fails


def perturb(node: object) -> object:
    """The values tree with every number moved far enough to change any figure printed from it."""
    if is_leaf(node):
        value = node["value"]
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return value
        return value + 1 if float(value).is_integer() else value + 1.37 * max(abs(value), 1)
    if isinstance(node, dict):
        return {key: perturb(child) for key, child in node.items()}
    return node


SECTION = re.compile(r'<section id="([^"]+)"(.*?)</section>', re.S)


def printed_figures(html_text: str, date: str) -> list[tuple[str, list[str]]]:
    """Figures per slide of a rendered deck: text and aria-labels, markup stripped."""
    out = []
    for sid, body in SECTION.findall(html_text):
        text = " ".join(TEXT_ATTRIBUTE.findall(body)) + " " + TAG.sub(" ", body)
        text = strip_non_data(html.unescape(text), date)
        out.append((sid, [m.group(0) for m in NUMBER.finditer(text)]))
    return out


def check_sentinel(inputs: dict, html_text: str) -> list[str]:
    """Render again with every numeric leaf moved: a figure that stays put is not drawn from values.json."""
    moved = render_html(dict(inputs, v=perturb(inputs["raw"])))
    _, text_forms = number_forms(inputs["raw"])
    date = inputs["meta"]["date"]
    fails = []
    pairs = zip(printed_figures(html_text, date), printed_figures(moved, date))
    for page, ((sid, before), (_, after)) in enumerate(pairs, 1):
        if len(before) != len(after):
            fails.append(f"slide {page} ({sid}): {len(before)} figures, {len(after)} with moved values")
            continue
        spare = page_constants(page, sid)
        for figure, moved_figure in zip(before, after):
            if figure != moved_figure or figure in text_forms:
                continue
            if spare[figure] > 0:
                spare[figure] -= 1
                continue
            fails.append(f"slide {page} ({sid}): figure {figure!r} does not follow values.json")
    return fails


def word_counts(slides: list[dict]) -> dict[str, int]:
    return {s["id"]: len(s["text"].split()) for s in slides}


def check_words(counts: dict[str, int]) -> list[str]:
    fails = []
    ids = list(counts)
    for sid in ids[:MAIN_SLIDES]:
        limit = WORD_LIMITS.get(sid, CONTENT_WORD_LIMIT)
        if counts[sid] > limit:
            fails.append(f"{sid}: {counts[sid]} words, limit {limit}")
    main_total = sum(counts[sid] for sid in ids[:MAIN_SLIDES])
    if main_total > MAIN_WORD_LIMIT:
        fails.append(f"main slides: {main_total} words, limit {MAIN_WORD_LIMIT}")
    return fails


NOTES_HEADING = re.compile(r"^## (\d+)\. ([a-z0-9]+): (.+)$", re.M)


def split_notes(text: str) -> tuple[list[tuple[int, str, str, str]], str]:
    """(page, id, label, body) per section, and all bodies joined for the parity check."""
    heads = list(NOTES_HEADING.finditer(text))
    sections = []
    for i, m in enumerate(heads):
        end = heads[i + 1].start() if i + 1 < len(heads) else len(text)
        sections.append((int(m.group(1)), m.group(2), m.group(3).strip(), text[m.end():end].strip()))
    return sections, "\n".join(body for *_, body in sections)


def check_notes(text: str, slides: list[dict]) -> list[str]:
    fails = []
    if not text.startswith("# "):
        fails.append("speaker notes: the first line is not a title")
    sections, _ = split_notes(text)
    if len(sections) != len(slides):
        fails.append(f"speaker notes: {len(sections)} sections for {len(slides)} slides")
    for page, (section, slide) in enumerate(zip(sections, slides), 1):
        expected = (page, slide["id"], slide["label"])
        if section[:3] != expected:
            fails.append(f"speaker notes: section {section[:3]} where {expected} is expected")
        if not section[3]:
            fails.append(f"speaker notes: section {page} ({section[1]}) is empty")
    return fails


def check_determinism(first: dict, second: dict) -> list[str]:
    fails = []
    if first["html"] != second["html"]:
        fails.append("deck.html differs between two renders")
    fails += [f"{sid}: page raster differs between two renders"
              for sid in first["shots"] if first["shots"][sid] != second["shots"].get(sid)]
    if first["texts"] != second["texts"]:
        fails.append("PDF text layer differs between two renders")
    return fails


# --- Deck ------------------------------------------------------------------------------

def build_deck() -> list[str]:
    inputs = load_inputs()
    BUILD.mkdir(exist_ok=True)
    fails = lint_templates()
    html_text = render_html(inputs)
    DECK_HTML.write_bytes(html_text.encode("utf-8"))
    second_html = BUILD / "deck.second.html"
    second_html.write_bytes(render_html(inputs).encode("utf-8"))
    second_pdf = BUILD / "deck.second.pdf"
    with sync_playwright() as playwright:
        first = browser_pass(playwright, DECK_HTML, DECK_PDF)
        second = browser_pass(playwright, second_html, second_pdf)
    pdf_fails, texts = check_pdf(DECK_PDF)
    _, second_texts = check_pdf(second_pdf)
    first.update(html=DECK_HTML.read_bytes(), texts=texts)
    second.update(html=second_html.read_bytes(), texts=second_texts)
    second_html.unlink()
    second_pdf.unlink()

    slides = first["slides"]
    notes = NOTES.read_text(encoding="utf-8") if NOTES.exists() else ""
    counts = word_counts(slides)
    dom_texts = [s["text"] for s in slides]
    date = inputs["meta"]["date"]
    if [s["id"] for s in slides] != list(SLIDES):
        fails.append(f"slides in the deck {[s['id'] for s in slides]} are not {list(SLIDES)}")
    fails += check_faces(first["faces"]) + first["fallbacks"] + check_fit(slides)
    fails += pdf_fails + check_text_layer(texts) + check_text_layer(dom_texts, "slide")
    fails += check_pdf_matches_html(texts, slides)
    fails += check_parity(inputs["raw"], [(s["id"], t) for s, t in zip(slides, texts)],
                          split_notes(notes)[1], date)
    fails += check_parity(inputs["raw"], [(s["id"], s["text"]) for s in slides], None, date, "slide")
    fails += check_sentinel(inputs, html_text)
    fails += check_words(counts) + check_notes(notes, slides) + check_notes_text(notes)
    fails += check_determinism(first, second)

    print(f"{'page':>4}  {'slide':8} {'words':>5}  {'lowest y':>8}  (content area ends at y {FLOW_LIMIT_Y})")
    for number, s in enumerate(slides, 1):
        over = f"  over by {s['lowest'] - FLOW_LIMIT_Y:.1f}" if s["lowest"] > FLOW_LIMIT_Y else ""
        print(f"{number:>4}  {s['id']:8} {counts[s['id']]:>5}  {s['lowest']:>8.1f}{over}")
    print(f"main slides: {sum(list(counts.values())[:MAIN_SLIDES])} words; "
          f"PDF {DECK_PDF.relative_to(REPO).as_posix()}: {len(texts)} pages, {DECK_PDF.stat().st_size:,} B")
    (BUILD / "deck_checks.json").write_text(json.dumps(
        {"words": counts, "lowest": {s["id"]: s["lowest"] for s in slides},
         "shots": first["shots"], "failures": fails}, indent=1), encoding="utf-8")
    return fails


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Render and check the executive deck.")
    which = parser.add_mutually_exclusive_group()
    which.add_argument("--deck", action="store_true", help="render and check the deck (the default)")
    which.add_argument("--report", action="store_true", help="reserved for the written report")
    args = parser.parse_args(argv)
    if args.report:
        parser.error("--report is reserved: the report template is not built yet")
    fails = build_deck()
    if fails:
        print(f"\n{len(fails)} check(s) failed:")
        for fail in fails:
            print(f"  - {fail}")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
