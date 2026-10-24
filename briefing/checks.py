"""Checks for the executive deck and the decision report.

render.py renders each document, prints it to PDF and measures its pages in Chromium with the
JavaScript below; the templates reach check_scale through render.py's on_scale guard. Every check
takes the spec of the document it checks (a render.Document) first and returns a list of
failures, empty when the check passes. The spec supplies what differs between the documents:
page size and count, flow limit, the pages with a .cap-top note, word limits, the non-data
constants and the speaker notes, if any. check_readme_finding, run with each document, holds
the figures of README.md's "The finding" to the same parity rules and takes no spec.
"""

from __future__ import annotations

import collections
import html
import pathlib
import re
import unicodedata

from pypdf import PdfReader


# --- Values tree -----------------------------------------------------------------------

def is_leaf(node: object) -> bool:
    """A values.json leaf: {class, unit, value, ...}."""
    return isinstance(node, dict) and "value" in node and "unit" in node


def leaves(node: object, path: str = ""):
    if is_leaf(node):
        yield path, node
    elif isinstance(node, dict):
        for key, child in node.items():
            yield from leaves(child, f"{path}.{key}" if path else key)


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


# --- Template lint ---------------------------------------------------------------------

JINJA = re.compile(r"\{\{.*?\}\}|\{%.*?%\}|\{#.*?#\}", re.S)
STRING_LITERAL = re.compile(r"""(["'])(.*?)\1""")
TAG = re.compile(r"<[^>]*>", re.S)
TEXT_ATTRIBUTE = re.compile(r'\b(?:aria-label|alt|title)="([^"]*)"')
ENTITY = re.compile(r"&#?\w+;")
HEX_COLOUR = re.compile(r"(?<![&\w])#[0-9A-Fa-f]{3,8}\b")
COLOUR_FUNCTION = re.compile(r"\b(?:rgba?|hsla?)\(", re.I)
# String literals that name a template, a path part or a page id, not a figure.
TEMPLATE_NAME = re.compile(r"[a-z][a-z0-9_]*$|[\w/.-]*\.j2$")


def lint_templates(doc, root: pathlib.Path) -> list[str]:
    """Colours only through var(--...); no figure typed into template text. Reads the files of
    `doc.template_files` under `root`; text matching `doc.lint_non_data` may carry digits."""
    paths = sorted({path for pattern in doc.template_files for path in root.glob(pattern)
                    if path.is_file()})
    fails = []
    for path in paths:
        rel = path.relative_to(root.parent).as_posix()
        source = path.read_text(encoding="utf-8")
        fails += [f"{rel}: colour literal {m.group(0)}" for m in HEX_COLOUR.finditer(source)]
        fails += [f"{rel}: colour function {m.group(0)}"
                  for m in COLOUR_FUNCTION.finditer(source)]
        if path.suffix == ".css":
            continue
        texts = [lit for tag in JINJA.findall(source) for _, lit in STRING_LITERAL.findall(tag)
                 if not TEMPLATE_NAME.match(lit)]
        markup = JINJA.sub(" ", source)
        texts += TEXT_ATTRIBUTE.findall(markup)
        texts.append(TAG.sub(" ", markup))
        for text in texts:
            text = doc.lint_non_data.sub(" ", ENTITY.sub(" ", text))
            fails += [f"{rel}: figure typed into the template: {m.group(0)!r}"
                      for m in re.finditer(r"\d[\d,.]*", text)]
    return fails


# --- Chart scales ----------------------------------------------------------------------

def check_scale(doc, exhibit: int, figure: str, value: float, limit: float) -> list[str]:
    """A figure a template draws on a fixed-length scale must lie in (0, limit], limit being the
    template's scale constant; past it, the bar or track would run beyond its length."""
    if 0 < value <= limit:
        return []
    return [f"{doc.name}: Exhibit {exhibit}: {figure} is {value:g}, outside the scale "
            f"(0, {limit:g}]"]


# --- Browser measurements --------------------------------------------------------------

JS_FACES = """() => [...document.fonts].map(f => ({
  family: f.family.replace(/"/g, ''), weight: String(f.weight), style: f.style,
  status: f.status}))"""

# Per page (the elements matching the selector): id, the .label text, the rendered text, the
# box size, boxes outside the page, children spilling out of a box sized in the template,
# elements whose text overflows, and the lowest bottom edge outside the footer.
JS_PAGES = """(selector) => [...document.querySelectorAll(selector)].map(s => {
  const box = s.getBoundingClientRect();
  const label = s.querySelector('.label');
  const out = {id: s.id, label: label ? label.textContent : '', text: s.innerText,
               size: [box.width, box.height], outside: [], spill: [], overflow: [], lowest: 0};
  for (const el of s.querySelectorAll('*')) {
    const r = el.getBoundingClientRect();
    const name = el.tagName.toLowerCase() + ' "' +
      (el.textContent || '').trim().slice(0, 40) + '"';
    if ((r.width || r.height) && (r.left < box.left - 0.5 || r.top < box.top - 0.5 ||
        r.right > box.right + 0.5 || r.bottom > box.bottom + 0.5)) out.outside.push(name);
    if (el.style.width || el.style.height) {
      // A box sized in the template (a bar, a column, a chart frame) must hold its children.
      for (const child of el.children) {
        const c = child.getBoundingClientRect();
        if (c.left < r.left - 0.5 || c.top < r.top - 0.5 ||
            c.right > r.right + 0.5 || c.bottom > r.bottom + 0.5)
          out.spill.push(name + ' > ' + child.tagName.toLowerCase() + ' "' +
                         child.textContent.trim().slice(0, 30) + '"');
      }
    }
    const cs = getComputedStyle(el);
    const holdsText = [...el.childNodes].some(n => n.textContent.trim() &&
      (n.nodeType === 3 || (n.nodeType === 1 && getComputedStyle(n).display === 'inline')));
    if (holdsText && cs.display !== 'inline') {
      // With a line-height below the font's content area (1.2 em for Lato), glyph boxes reach
      // past the line box by half the difference; that is layout, not overflowing text. A line
      // can mix font sizes, so the largest excess among the element's text nodes counts.
      const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT, {acceptNode: n =>
        n.textContent.trim() ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP});
      const range = document.createRange();
      const lineHeight = parseFloat(cs.lineHeight);
      let slack = 1;
      for (let n = walker.nextNode(); n; n = walker.nextNode()) {
        range.selectNodeContents(n);
        const glyph = range.getClientRects()[0];
        if (glyph && lineHeight) slack = Math.max(slack, (glyph.height - lineHeight) / 2 + 1);
      }
      if (el.scrollWidth > el.clientWidth + 1 || el.scrollHeight > el.clientHeight + slack)
        out.overflow.push(name);
    }
    if (!el.closest('.foot')) out.lowest = Math.max(out.lowest, r.bottom - box.top);
  }
  return out;
})"""


# Per page named in the spec's cap_top_pages: the number of .cap-top notes and of elements marked
# data-cap-top-anchor; with one of each, the note's computed text-box-trim and text-box-edge, the
# top of its box and of the anchor's, its first baseline (a zero-size inline-block probe, inserted
# and removed again) and the cap height of its font (the ink of "H" in Lato at its weight, drawn
# at 1000 px on a canvas), all in px from the top of the page.
JS_CAP_TOP = """([selector, ids]) => [...document.querySelectorAll(selector)]
    .filter(s => ids.includes(s.id)).map(s => {
  const notes = s.querySelectorAll('.cap-top');
  const anchors = s.querySelectorAll('[data-cap-top-anchor]');
  const out = {id: s.id, notes: notes.length, anchors: anchors.length};
  if (notes.length !== 1 || anchors.length !== 1) return out;
  const note = notes[0], top = s.getBoundingClientRect().top;
  const probe = document.createElement('span');
  probe.style.cssText = 'display:inline-block;width:0;height:0;vertical-align:baseline';
  note.insertBefore(probe, note.firstChild);
  out.baseline = probe.getBoundingClientRect().bottom - top;
  probe.remove();
  const cs = getComputedStyle(note);
  const ctx = document.createElement('canvas').getContext('2d');
  ctx.font = `${cs.fontWeight} 1000px Lato`;
  out.cap = ctx.measureText('H').actualBoundingBoxAscent / 1000 * parseFloat(cs.fontSize);
  out.trim = cs.textBoxTrim;
  out.edge = cs.textBoxEdge;
  out.note_top = note.getBoundingClientRect().top - top;
  out.anchor_top = anchors[0].getBoundingClientRect().top - top;
  return out;
})"""


def font_fallbacks(doc, page) -> list[str]:
    """Every text node must be drawn with the loaded Lato web font, never a platform fallback."""
    cdp = page.context.new_cdp_session(page)
    cdp.send("DOM.enable")
    cdp.send("CSS.enable")
    root = cdp.send("DOM.getDocument", {"depth": -1})["root"]["nodeId"]
    nodes = cdp.send("DOM.querySelectorAll", {"nodeId": root, "selector": f"{doc.page_tag} *"})
    fails = []
    for node in nodes["nodeIds"]:
        fonts = cdp.send("CSS.getPlatformFontsForNode", {"nodeId": node})["fonts"]
        bad = [f"{f['familyName']} ({f['glyphCount']} glyphs)" for f in fonts
               if not (f["isCustomFont"] and f["familyName"].startswith("Lato"))]
        if bad:
            html_text = cdp.send("DOM.getOuterHTML", {"nodeId": node})["outerHTML"]
            fails.append(f"font fallback {', '.join(bad)} in {TAG.sub('', html_text)[:60]!r}")
    cdp.detach()
    return fails


# --- Fonts, page fit, PDF --------------------------------------------------------------

def check_faces(doc, faces: list[dict]) -> list[str]:
    fails = []
    for weight in doc.faces:
        found = [f for f in faces
                 if f["family"] == "Lato" and f["weight"] == weight and f["style"] == "normal"]
        if not found:
            fails.append(f"font face Lato {weight} is not declared")
        elif found[0]["status"] != "loaded":
            fails.append(f"font face Lato {weight} is {found[0]['status']}, not loaded")
    return fails


def check_fit(doc, pages: list[dict]) -> list[str]:
    width, height = doc.page_px
    fails = []
    for s in pages:
        w, h = s["size"]
        if abs(w - width) > doc.page_px_tolerance or abs(h - height) > doc.page_px_tolerance:
            fails.append(f"{s['id']}: {doc.unit} is {w:g} x {h:g} px, not {width:g} x {height:g}")
        fails += [f"{s['id']}: box outside the {doc.unit}: {name}" for name in s["outside"]]
        fails += [f"{s['id']}: child spills out of its sized box: {name}" for name in s["spill"]]
        fails += [f"{s['id']}: text overflows its box: {name}" for name in s["overflow"]]
        if s["lowest"] > doc.flow_limit:
            fails.append(f"{s['id']}: content ends at y {s['lowest']:.1f}, "
                         f"past {doc.flow_limit:g}")
    return fails


CAP_TOP = ("trim-start", "cap alphabetic")  # computed text-box-trim and text-box-edge
CAP_TOP_TOLERANCE = 0.5  # px


def check_cap_top(doc, measured: list[dict]) -> list[str]:
    """Each page in doc.cap_top_pages holds one .cap-top note and one table marked
    data-cap-top-anchor. The note's cap trim must be applied, so that its box starts at its first
    line's cap height (baseline less the cap height of its font), and that box top must be level
    with the table's, each within CAP_TOP_TOLERANCE. measured: JS_CAP_TOP's result."""
    by_id = {m["id"]: m for m in measured}
    fails = []
    for sid in doc.cap_top_pages:
        m = by_id.get(sid)
        if m is None:
            fails.append(f"{sid}: no such {doc.unit} for the cap-height alignment")
            continue
        if (m["notes"], m["anchors"]) != (1, 1):
            fails.append(f"{sid}: {m['notes']} .cap-top note(s) and {m['anchors']} table(s) marked "
                         "data-cap-top-anchor, not one of each")
            continue
        trim = (m.get("trim"), m.get("edge"))
        if trim != CAP_TOP:
            fails.append(f"{sid}: .cap-top has text-box-trim {trim[0]!r} and text-box-edge "
                         f"{trim[1]!r}, not {CAP_TOP[0]!r} and {CAP_TOP[1]!r}")
        cap_line = m["baseline"] - m["cap"]
        if abs(cap_line - m["note_top"]) > CAP_TOP_TOLERANCE:
            fails.append(f"{sid}: .cap-top box starts at y {m['note_top']:.2f}, not at its cap "
                         f"height, y {cap_line:.2f} (baseline {m['baseline']:.2f} less cap height "
                         f"{m['cap']:.2f})")
        if abs(m["note_top"] - m["anchor_top"]) > CAP_TOP_TOLERANCE:
            fails.append(f"{sid}: .cap-top box starts at y {m['note_top']:.2f}, not level with its "
                         f"table at y {m['anchor_top']:.2f}")
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


def check_pdf(doc, path: pathlib.Path) -> tuple[list[str], list[str]]:
    """Page count and size, Lato only and embedded, the Title; also returns the per-page text."""
    reader = PdfReader(path)
    width, height = doc.page_pt
    fails = []
    if len(reader.pages) != len(doc.pages):
        fails.append(f"PDF has {len(reader.pages)} pages, not {len(doc.pages)}")
    for number, page in enumerate(reader.pages, 1):
        size = (float(page.mediabox.width), float(page.mediabox.height))
        if any(abs(a - b) > doc.page_pt_tolerance for a, b in zip(size, doc.page_pt)):
            fails.append(f"PDF page {number} is {size[0]:g} x {size[1]:g} pt, "
                         f"not {width:g} x {height:g}")
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
    if title != doc.title:
        fails.append(f"PDF Title is {title!r}, not {doc.title!r}")
    return sorted(set(fails), key=fails.index), [page.extract_text() for page in reader.pages]


# --- Text layer ------------------------------------------------------------------------

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


def check_text_layer(doc, texts: list[str], where: str = "PDF page") -> list[str]:
    """Banned forms per page. Run on the PDF text layer and on each page's DOM text: letter-spaced
    labels can come out of the PDF as single spaced letters, which no word pattern matches."""
    fails = []
    for number, text in enumerate(texts, 1):
        for pattern, what in FORBIDDEN_TEXT:
            fails += [f"{where} {number}: {what}: {m.group(0)!r}" for m in pattern.finditer(text)]
    if not any("×" in text for text in texts):
        fails.append(f"{where} text has no × sign")
    return fails


def check_notes_text(doc, text: str) -> list[str]:
    """The notes are read aloud, so "percent" and "times" stay; "EUR", dashes and quotes do not."""
    return [f"speaker notes: {what}: {m.group(0)!r}"
            for pattern, what in FORBIDDEN_TEXT[1:4] for m in pattern.finditer(text)]


def check_pdf_matches_html(doc, texts: list[str], pages: list[dict]) -> list[str]:
    """Each PDF page carries the same characters as its page's DOM text (whitespace aside)."""
    def chars(text: str) -> collections.Counter:
        return collections.Counter(c for c in unicodedata.normalize("NFKC", text)
                                   if not c.isspace())
    fails = []
    for number, (text, page) in enumerate(zip(texts, pages), 1):
        pdf_chars, dom_chars = chars(text), chars(page["text"])
        if pdf_chars != dom_chars:
            fails.append(f"PDF page {number} text differs from the HTML: only in PDF "
                         f"{dict(pdf_chars - dom_chars)}, "
                         f"only in HTML {dict(dom_chars - pdf_chars)}")
    return fails


# --- Figure parity ---------------------------------------------------------------------

NUMBER = re.compile(r"(?<![\w.,])(€?)(\d{1,3}(?:,\d{3})+|\d+)(\.\d+)?([%×KM]?)(?!\w)")
LABEL_WITH_DIGIT = re.compile(r"\b[A-Za-z]+\d+\b")
UNIT_WORD = re.compile(r"\s+(percent|euros|times)\b")  # how the notes say %, € and ×
UNIT_OF = {"€": "eur", "%": "pct", "×": "ratio", "euros": "eur", "percent": "pct",
           "times": "ratio"}


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


def strip_non_data(doc, text: str, date: str) -> str:
    """Remove the date and the document's non-data phrases (stage names, the per-1,000 unit)."""
    text = text.replace(date, " ") if date else text
    for pattern, replacement in doc.non_data_text:
        text = pattern.sub(replacement, text)
    return text


SPACED_LETTERS = re.compile(r"(?<!\S)\S(?: \S){2,}(?!\S)")
LETTER_DIGIT = re.compile(r"(?<=[^\W\d_])(?=\d)|(?<=\d)(?=[^\W\d_])")


def join_spaced_letters(text: str) -> str:
    """Letter-spaced labels can come out of the PDF text layer as single characters with a space
    between each ("1 5 %  D I S C O U N T"); runs of three or more are joined, and split again
    where a letter meets a digit, as one run can hold the end of one label and the start of the
    next."""
    return SPACED_LETTERS.sub(lambda m: LETTER_DIGIT.sub(" ", m.group(0).replace(" ", "")), text)


def page_constants(doc, page: int | None, page_id: str | None) -> collections.Counter:
    """Figures that are layout, not data: the page number and the document's page constants."""
    spare = collections.Counter({str(page): 1} if page else {})
    spare.update(doc.constants.get(page_id, {}))
    return spare


def check_parity(doc, raw: dict, pages: list[tuple[str, str]], notes_body: str | None,
                 date: str, where: str = "PDF page") -> list[str]:
    """pages: (page id, text). Figures must be values.json leaves of their unit at some
    precision."""
    forms, text_forms = number_forms(raw)
    fails = []
    sources = [(f"{where} {n} ({sid})", text, n, sid) for n, (sid, text) in enumerate(pages, 1)]
    if notes_body is not None:
        sources.append(("speaker notes", notes_body, None, None))
    for label, text, number, sid in sources:
        text = join_spaced_letters(text)
        fails += [f"{label}: retired figure or phrase {m.group(0)!r}"
                  for m in RETIRED.finditer(text)]
        text = strip_non_data(doc, text, date)
        fails += [f"{label}: unexpected label {m.group(0)!r}"
                  for m in LABEL_WITH_DIGIT.finditer(text) if m.group(0) not in doc.labels]
        spare = page_constants(doc, number, sid)
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


def printed_figures(doc, html_text: str, date: str) -> list[tuple[str, list[str]]]:
    """Figures per page of a rendered document: text and aria-labels, markup stripped."""
    page_markup = re.compile(rf'<{doc.page_tag} id="([^"]+)"(.*?)</{doc.page_tag}>', re.S)
    out = []
    for sid, body in page_markup.findall(html_text):
        text = " ".join(TEXT_ATTRIBUTE.findall(body)) + " " + TAG.sub(" ", body)
        text = strip_non_data(doc, html.unescape(text), date)
        out.append((sid, [m.group(0) for m in NUMBER.finditer(text)]))
    return out


def check_sentinel(doc, raw: dict, date: str, html_text: str, moved_html: str) -> list[str]:
    """moved_html is the document rendered with every numeric leaf perturbed: a figure that
    stays put is not drawn from values.json."""
    _, text_forms = number_forms(raw)
    fails = []
    pairs = zip(printed_figures(doc, html_text, date), printed_figures(doc, moved_html, date))
    for page, ((sid, before), (_, after)) in enumerate(pairs, 1):
        if len(before) != len(after):
            fails.append(f"{doc.unit} {page} ({sid}): {len(before)} figures, "
                         f"{len(after)} with moved values")
            continue
        spare = page_constants(doc, page, sid)
        for figure, moved_figure in zip(before, after):
            if figure != moved_figure or figure in text_forms:
                continue
            if spare[figure] > 0:
                spare[figure] -= 1
                continue
            fails.append(f"{doc.unit} {page} ({sid}): figure {figure!r} does not follow "
                         "values.json")
    return fails


# --- README finding --------------------------------------------------------------------

README_SECTION = "## The finding"
README_UNIT_WORD = re.compile(r" (EUR|times)\b")  # how the README writes € and ×
README_UNIT_OF = dict(UNIT_OF, EUR="eur")
README_PER_1000 = re.compile(r"1,000 EUR of discount\b")  # the unit of the per-1,000 figures
LINK_TARGET = re.compile(r"\]\([^)]*\)")


def readme_figures(text: str) -> list[tuple[int, str, str | None, str]] | None:
    """(line number, figure as written, unit, digits) for each number in the README's "The
    finding", from its heading to the next "## " heading, link targets aside; None without the
    section. The unit is the one the README writes: "%" pct, "EUR" eur, "times" ratio, none on a
    whole number count; "per-1,000" for the unit of "1,000 EUR of discount"; None for a decimal
    without a unit, for a K or M figure and for a word whose digits NUMBER does not read whole
    (a unit glued on, "2,466EUR"), the word then being the figure."""
    lines = text.splitlines()
    if README_SECTION not in lines:
        return None
    start = lines.index(README_SECTION) + 1
    figures = []
    for number, line in enumerate(lines[start:], start + 1):
        if line.startswith("## "):
            break
        line = LINK_TARGET.sub("]", line)
        masked = NUMBER.sub(lambda m: " " * len(m.group(0)), line)
        unread = [w.span() for w in re.finditer(r"\S+", line)
                  if re.search(r"\d", masked[w.start():w.end()])]
        found = [(start, line[start:end], None, line[start:end]) for start, end in unread]
        for m in NUMBER.finditer(line):
            if any(start <= m.start() < end for start, end in unread):
                continue
            sign, whole, decimals, suffix = m.groups()
            word = README_UNIT_WORD.match(line, m.end())
            written = m.group(0) + (word.group(0) if word else "")
            unit = README_UNIT_OF.get(sign or suffix or (word.group(1) if word else ""))
            if README_PER_1000.match(line, m.start()):
                unit = "per-1,000"
            elif unit is None and not decimals and not suffix:
                unit = "count"
            found.append((m.start(), written, unit, whole + (decimals or "")))
        figures += [(number, *figure[1:]) for figure in sorted(found, key=lambda f: f[0])]
    return figures


def check_readme_finding(raw: dict, text: str) -> list[str]:
    """The README's "The finding" under the documents' figure-parity rule: each figure a
    values.json leaf of the unit it is written in, at the precision written. text: README.md."""
    figures = readme_figures(text)
    if figures is None:
        return [f'README.md: no "{README_SECTION}" section']
    if all(unit == "per-1,000" for _, _, unit, _ in figures):
        return [f'README.md: "{README_SECTION}" holds no figures']
    forms, _ = number_forms(raw)
    fails = []
    for line, written, unit, digits in figures:
        if unit == "per-1,000":
            continue
        if unit is None:
            fails.append(f"README.md:{line}: figure {written!r} has no unit the check reads "
                         "(%, EUR, times, or none on a whole number count)")
        elif digits not in forms[unit]:
            fails.append(f"README.md:{line}: figure {written!r} is not a values.json leaf "
                         f"with unit {unit} at the precision written")
    return fails


# --- Words and speaker notes -----------------------------------------------------------

def word_counts(pages: list[dict]) -> dict[str, int]:
    """Whitespace-separated tokens of each page's rendered text."""
    return {s["id"]: len(s["text"].split()) for s in pages}


def check_words(doc, counts: dict[str, int]) -> list[str]:
    fails = []
    for sid, limit in doc.word_limits.items():
        if counts.get(sid, 0) > limit:
            fails.append(f"{sid}: {counts[sid]} words, limit {limit}")
    if doc.main_word_limit is not None:
        main_total = sum(counts[sid] for sid in list(counts)[:doc.main_pages])
        if main_total > doc.main_word_limit:
            fails.append(f"main {doc.unit}s: {main_total} words, limit {doc.main_word_limit}")
    return fails


NOTES_HEADING = re.compile(r"^## (\d+)\. ([a-z0-9]+): (.+)$", re.M)


def split_notes(text: str) -> tuple[list[tuple[int, str, str, str]], str]:
    """(page, id, label, body) per section, and all bodies joined for the parity check."""
    heads = list(NOTES_HEADING.finditer(text))
    sections = []
    for i, m in enumerate(heads):
        end = heads[i + 1].start() if i + 1 < len(heads) else len(text)
        sections.append((int(m.group(1)), m.group(2), m.group(3).strip(),
                         text[m.end():end].strip()))
    return sections, "\n".join(body for *_, body in sections)


def check_notes(doc, text: str, pages: list[dict]) -> list[str]:
    fails = []
    if not text.startswith("# "):
        fails.append("speaker notes: the first line is not a title")
    sections, _ = split_notes(text)
    if len(sections) != len(pages):
        fails.append(f"speaker notes: {len(sections)} sections for {len(pages)} {doc.unit}s")
    for page, (section, slide) in enumerate(zip(sections, pages), 1):
        expected = (page, slide["id"], slide["label"])
        if section[:3] != expected:
            fails.append(f"speaker notes: section {section[:3]} where {expected} is expected")
        if not section[3]:
            fails.append(f"speaker notes: section {page} ({section[1]}) is empty")
    return fails


# --- Colour contrast and the report's text colours -------------------------------------

# Per rendered text node of each page: its colour (SVG text: the fill), the background behind it
# (the nearest opaque background colour of its element or an ancestor; for SVG text, from the svg
# element up; the white canvas if there is none), its font size and weight. A background image or
# a translucent background on the way leaves the text unmeasured.
JS_TEXT_COLOURS = """(selector) => {
  const SVG = 'http://www.w3.org/2000/svg';
  const out = [];
  document.querySelectorAll(selector).forEach((pageEl, index) => {
    const walker = document.createTreeWalker(pageEl, NodeFilter.SHOW_TEXT, {acceptNode: n =>
      n.textContent.trim() ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP});
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const range = document.createRange();
      range.selectNodeContents(node);
      if (![...range.getClientRects()].some(r => r.width && r.height)) continue;
      const el = node.parentElement;
      const cs = getComputedStyle(el);
      const svg = el.namespaceURI === SVG;
      let background = '', unmeasured = '';
      for (let a = svg ? el.closest('svg') : el; a && !background; a = a.parentElement) {
        const s = getComputedStyle(a);
        if (s.backgroundImage !== 'none') { unmeasured = 'a background image'; break; }
        const channels = (s.backgroundColor.match(/[\\d.]+/g) || [0, 0, 0, 0]).map(Number);
        const alpha = channels.length > 3 ? channels[3] : 1;
        if (alpha === 1) background = s.backgroundColor;
        else if (alpha > 0) { unmeasured = 'a translucent background'; break; }
      }
      if (!background && !unmeasured) background = 'rgb(255, 255, 255)';
      out.push({page: index + 1, id: pageEl.id, text: node.textContent.trim().slice(0, 40),
                color: svg ? cs.fill : cs.color, background, unmeasured,
                size: parseFloat(cs.fontSize), weight: parseInt(cs.fontWeight, 10)});
    }
  });
  return out;
}"""

RGB = re.compile(r"rgba?\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)(?:\s*[,/]\s*([\d.]+))?\s*\)")


def parse_colour(css: str) -> tuple[str, float] | None:
    """A computed rgb()/rgba() colour as ('#RRGGBB', alpha); None for any other form."""
    m = RGB.fullmatch(css.strip())
    if not m:
        return None
    r, g, b, alpha = m.groups()
    hex_value = "#" + "".join(f"{round(float(c)):02X}" for c in (r, g, b))
    return hex_value, 1.0 if alpha is None else float(alpha)


def _linear_rgb(hex_color: str) -> tuple:
    out = []
    for i in (0, 2, 4):
        v = int(hex_color.lstrip("#")[i:i + 2], 16) / 255
        out.append(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4)
    return tuple(out)


def luminance(hex_color: str) -> float:
    """WCAG 2 relative luminance."""
    r, g, b = _linear_rgb(hex_color)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a: str, b: str) -> float:
    """WCAG 2 contrast ratio."""
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


# WCAG 2 large text: 18 pt, or 14 pt at bold weight.
LARGE_TEXT_PX = 24
LARGE_BOLD_TEXT_PX = 18.66


def check_contrast(doc, runs: list[dict]) -> list[str]:
    """Every rendered text node reaches 4.5:1 on its background, or 3:1 as large text."""
    fails = []
    for run in runs:
        where = f"{doc.unit} {run['page']} ({run['id']}): {run['text']!r}"
        fg = parse_colour(run["color"])
        bg = parse_colour(run["background"]) if run["background"] else None
        if run["unmeasured"] or fg is None or bg is None or fg[1] < 1:
            reason = run["unmeasured"] or f"colour {run['color']} on {run['background'] or '?'}"
            fails.append(f"{where}: contrast unmeasured ({reason})")
            continue
        large = run["size"] >= LARGE_TEXT_PX or (
            run["size"] >= LARGE_BOLD_TEXT_PX and run["weight"] >= 700)
        floor = 3.0 if large else 4.5
        ratio = contrast(fg[0], bg[0])
        if ratio < floor:
            fails.append(f"{where}: contrast {ratio:.2f}:1 ({fg[0]} on {bg[0]}, "
                         f"{run['size']:g} px), below {floor:g}:1")
    return fails


def oklab(hex_color: str) -> tuple:
    r, g, b = _linear_rgb(hex_color)
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


def from_oklab(lab: tuple) -> str:
    """Inverse of oklab(); the colour must fall inside the sRGB gamut."""
    L, a, b = lab
    l, m, s = ((L + 0.3963377774 * a + 0.2158037573 * b) ** 3,
               (L - 0.1055613458 * a - 0.0638541728 * b) ** 3,
               (L - 0.0894841775 * a - 1.2914855480 * b) ** 3)
    out = "#"
    for v in (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
              -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
              -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s):
        if not 0 <= v <= 1:
            raise ValueError(f"OKLab {lab} is outside the sRGB gamut")
        srgb = 12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055
        out += f"{round(srgb * 255):02X}"
    return out


def darken(color: str, passes) -> str:
    """First OKLab lightness step (0.01) down from the colour, hue and chroma held, that passes;
    the method of the exhibits notebook."""
    L, a, b = oklab(color)
    for step in range(1, 101):
        shade = from_oklab((L - step / 100, a, b))
        if passes(shade):
            return shade
    raise ValueError(f"no darker step of {color} passes")


# The report's segment and accent colours: each key of notebooks/_brand.yml is its base darkened
# to the first step that reaches 4.5:1 on the three surfaces.
TEXT_COLOURS = {"at-risk-text": "at-risk", "hibernating-text": "hibernating-focus",
                "accent-text": "c1"}
TEXT_SURFACES = ("background", "page", "cover")


def check_palette(doc, palette: dict[str, str]) -> list[str]:
    """palette: the custom properties base.html.j2 writes, by name."""
    surfaces = [palette[name] for name in TEXT_SURFACES]
    fails = []
    for key, base in TEXT_COLOURS.items():
        if key not in palette:
            fails.append(f"palette: {key} is missing")
            continue
        expected = darken(palette[base], lambda c: all(contrast(c, s) >= 4.5 for s in surfaces))
        if palette[key].upper() != expected:
            fails.append(f"palette: {key} is {palette[key]}, not {expected} ({base} "
                         f"{palette[base]} darkened to 4.5:1 on {', '.join(surfaces)})")
    return fails


# --- Determinism -----------------------------------------------------------------------

def check_determinism(doc, first: dict, second: dict) -> list[str]:
    fails = []
    if first["html"] != second["html"]:
        fails.append(f"{doc.html.name} differs between two renders")
    fails += [f"{sid}: page raster differs between two renders"
              for sid in first["shots"] if first["shots"][sid] != second["shots"].get(sid)]
    if first["texts"] != second["texts"]:
        fails.append("PDF text layer differs between two renders")
    return fails
