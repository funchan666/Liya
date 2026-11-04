from pathlib import Path
import sys
import re
from xml.sax.saxutils import escape
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import KeepTogether, Paragraph, SimpleDocTemplate

base = Path(__file__).resolve().parent
pdfmetrics.registerFont(TTFont("LiyaArial", "/System/Library/Fonts/Supplemental/Arial.ttf"))
pdfmetrics.registerFont(TTFont("LiyaArialBold", "/System/Library/Fonts/Supplemental/Arial Bold.ttf"))
styles = {
    "title": ParagraphStyle("title", fontName="LiyaArialBold", fontSize=21, leading=26, textColor=colors.HexColor("#28356D"), spaceAfter=10),
    "heading": ParagraphStyle("heading", fontName="LiyaArialBold", fontSize=12, leading=16, textColor=colors.HexColor("#5A42B8"), spaceBefore=12, spaceAfter=6, keepWithNext=True),
    "body": ParagraphStyle("body", fontName="LiyaArial", fontSize=10.5, leading=14.5, textColor=colors.HexColor("#20243B"), spaceAfter=8, allowWidows=0, allowOrphans=0),
}
def inline_markup(text):
    result, position = [], 0
    for match in re.finditer(r"\[([^\]]+)\]\((https://[^\s)]+)\)", text):
        result.append(escape(text[position:match.start()]))
        result.append('<link href="' + escape(match.group(2), {'"': '&quot;'}) + '" color="#5042a3">' + escape(match.group(1)) + '</link>')
        position = match.end()
    result.append(escape(text[position:]))
    return ''.join(result)

for name in (sys.argv[1:] or ["terms", "privacy"]):
    doc = SimpleDocTemplate(str(base / f"{name}.pdf"), pagesize=(148 * mm, 210 * mm),
                            leftMargin=15 * mm, rightMargin=15 * mm, topMargin=16 * mm,
                            bottomMargin=16 * mm, title=f"Liya {name.title()}")
    story, section = [], []
    for block in (base / f"{name}.md").read_text(encoding="utf-8").strip().split("\n\n"):
        if block.startswith("# "):
            story.append(Paragraph(escape(block[2:]), styles["title"]))
        elif block.startswith("## "):
            if section: story.extend(section)
            section = [Paragraph(escape(block[3:]), styles["heading"])]
        else:
            (section if section else story).append(Paragraph(inline_markup(block.replace("\n", " ")), styles["body"]))
    if section: story.extend(section)
    doc.build(story)
