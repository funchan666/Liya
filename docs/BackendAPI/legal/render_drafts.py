from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import SimpleDocTemplate, Paragraph, KeepTogether

BASE = Path(__file__).resolve().parent
pdfmetrics.registerFont(TTFont("LiyaArial", "/System/Library/Fonts/Supplemental/Arial.ttf"))
pdfmetrics.registerFont(TTFont("LiyaArialBold", "/System/Library/Fonts/Supplemental/Arial Bold.ttf"))
styles = {
    "title": ParagraphStyle("title", fontName="LiyaArialBold", fontSize=21, leading=26, textColor=colors.HexColor("#28356D"), spaceAfter=10),
    "heading": ParagraphStyle("heading", fontName="LiyaArialBold", fontSize=12, leading=16, textColor=colors.HexColor("#5A42B8"), spaceBefore=12, spaceAfter=6),
    "body": ParagraphStyle("body", fontName="LiyaArial", fontSize=10.5, leading=15.5, alignment=TA_LEFT, textColor=colors.HexColor("#20243B"), spaceAfter=8),
}

for name in ("terms", "privacy"):
    source = (BASE / f"{name}.draft.md").read_text(encoding="utf-8")
    document = SimpleDocTemplate(str(BASE / f"{name}.draft.pdf"), pagesize=(148 * mm, 210 * mm),
                                 leftMargin=15 * mm, rightMargin=15 * mm,
                                 topMargin=16 * mm, bottomMargin=16 * mm,
                                 title=f"Liya {name.title()} — Draft")
    story, section = [], []
    for block in source.strip().split("\n\n"):
        if block.startswith("# "):
            story.append(Paragraph(escape(block[2:]), styles["title"]))
        elif block.startswith("## "):
            if section:
                story.append(KeepTogether(section))
            section = [Paragraph(escape(block[3:]), styles["heading"])]
        else:
            paragraph = Paragraph(escape(block.replace("\n", " ")), styles["body"])
            (section if section else story).append(paragraph)
    if section:
        story.append(KeepTogether(section))
    document.build(story)
