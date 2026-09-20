from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import LETTER
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import KeepTogether, Paragraph, SimpleDocTemplate, Spacer


OUTPUT = Path("output/pdf/Duy_Phong_Truong_Resume_Updated.pdf")
OUTPUT.parent.mkdir(parents=True, exist_ok=True)

NAVY = colors.HexColor("#17324D")
CHARCOAL = colors.HexColor("#23272B")
MUTED = colors.HexColor("#56616B")
RULE = colors.HexColor("#A9B4BE")

styles = getSampleStyleSheet()

name_style = ParagraphStyle(
    "Name",
    parent=styles["Normal"],
    fontName="Helvetica-Bold",
    fontSize=22,
    leading=25,
    textColor=NAVY,
    alignment=TA_CENTER,
    spaceAfter=3,
)

contact_style = ParagraphStyle(
    "Contact",
    parent=styles["Normal"],
    fontName="Helvetica",
    fontSize=9.8,
    leading=12,
    textColor=CHARCOAL,
    alignment=TA_CENTER,
    spaceAfter=9,
)

section_style = ParagraphStyle(
    "Section",
    parent=styles["Normal"],
    fontName="Helvetica-Bold",
    fontSize=11.2,
    leading=13.2,
    textColor=NAVY,
    spaceBefore=8,
    spaceAfter=4.5,
    borderWidth=0,
    borderPadding=0,
)

entry_style = ParagraphStyle(
    "Entry",
    parent=styles["Normal"],
    fontName="Helvetica",
    fontSize=10,
    leading=12.2,
    textColor=CHARCOAL,
    spaceAfter=1.8,
)

subentry_style = ParagraphStyle(
    "Subentry",
    parent=entry_style,
    fontSize=9.3,
    leading=11.2,
    textColor=MUTED,
    spaceAfter=2.5,
)

bullet_style = ParagraphStyle(
    "Bullet",
    parent=styles["Normal"],
    fontName="Helvetica",
    fontSize=9.7,
    leading=12.4,
    textColor=CHARCOAL,
    leftIndent=13,
    firstLineIndent=-8,
    bulletIndent=0,
    spaceBefore=0,
    spaceAfter=2,
)

skill_style = ParagraphStyle(
    "Skill",
    parent=entry_style,
    fontSize=9.5,
    leading=12,
    spaceAfter=1.5,
)


def section(title: str) -> list:
    return [Paragraph(title, section_style)]


def bullet(text: str) -> Paragraph:
    return Paragraph(text, bullet_style, bulletText="-")


def draw_page(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(RULE)
    canvas.setLineWidth(0.7)
    y = LETTER[1] - doc.topMargin - 50
    canvas.line(doc.leftMargin, y, LETTER[0] - doc.rightMargin, y)
    canvas.restoreState()


doc = SimpleDocTemplate(
    str(OUTPUT),
    pagesize=LETTER,
    rightMargin=0.58 * inch,
    leftMargin=0.58 * inch,
    topMargin=0.46 * inch,
    bottomMargin=0.46 * inch,
    title="Duy Phong Truong Resume",
    author="Duy Phong Truong",
    subject="Professional resume",
)

story = [
    Paragraph("Duy Phong Truong", name_style),
    Paragraph(
        '<link href="tel:6575659517" color="#23272B">657-565-9517</link>'
        '  |  <link href="mailto:truongduyphong2003@gmail.com" color="#23272B">'
        "truongduyphong2003@gmail.com</link>  |  Garden Grove, CA",
        contact_style,
    ),
]

story += section("EDUCATION")
story += [
    KeepTogether(
        [
            Paragraph("<b>Associate in Science, Electrical Engineering</b> | GPA: 3.96", entry_style),
            Paragraph("Golden West College | Huntington Beach, CA", subentry_style),
        ]
    ),
    KeepTogether(
        [
            Paragraph("<b>Associate in Science, Electrical Engineering</b> | GPA: 3.96", entry_style),
            Paragraph("Orange Coast College | Costa Mesa, CA", subentry_style),
        ]
    ),
]

story += section("RESEARCH EXPERIENCE")
story += [
    KeepTogether(
        [
            Paragraph(
                "<b>Research Assistant</b> | Transfer Pathways Summer Research Project, Computer Science",
                entry_style,
            ),
            Paragraph("California State University, Fullerton | May 2025 - July 2025", subentry_style),
            bullet(
                "Completed 100+ hours of research and data analysis, processing large datasets with Python, pandas, and Jupyter Notebook."
            ),
            bullet(
                "Prepared data for modeling with feature scaling and SMOTE; explored patterns using K-means clustering and PCA dimensionality reduction."
            ),
            bullet(
                "Trained and evaluated Random Forest models using ROC curves and confusion matrices, then presented findings to faculty and peers."
            ),
        ]
    )
]

story += section("PROFESSIONAL EXPERIENCE")
story += [
    KeepTogether(
        [
            Paragraph("<b>Math Tutor</b> | Golden West College", entry_style),
            Paragraph("August 2025 - Present", subentry_style),
            bullet(
                "Deliver one-on-one and group tutoring in algebra, calculus, and statistics, translating complex concepts into practical problem-solving strategies."
            ),
            bullet(
                "Collaborate with faculty to reinforce course learning outcomes and support academic success initiatives."
            ),
        ]
    )
]

story += section("VOLUNTEER EXPERIENCE")
story += [
    KeepTogether(
        [
            Paragraph(
                "<b>Volunteer Coordinator Assistant</b> | Vietnamese Catholic Student Association",
                entry_style,
            ),
            Paragraph("January 2025 - Present", subentry_style),
            bullet(
                "Support a team leader in coordinating 40+ volunteers who prepare and distribute meals to 200+ people experiencing homelessness each month."
            ),
            bullet("Manage the volunteer scheduling system and help organize monthly service logistics."),
        ]
    ),
    Spacer(1, 1.5),
    KeepTogether(
        [
            Paragraph(
                "<b>Volunteer</b> | Community Action Partnership of Orange County",
                entry_style,
            ),
            Paragraph("November 2024 - Present", subentry_style),
            bullet(
                "Pack, organize, and load essential supplies and donated goods for charitable distribution to people experiencing homelessness."
            ),
        ]
    ),
]

story += section("TECHNICAL SKILLS")
story += [
    Paragraph("<b>Programming and analytics:</b> Python, C++, pandas, Jupyter Notebook, data analysis", skill_style),
    Paragraph(
        "<b>Machine learning:</b> Random Forest, K-means clustering, PCA, feature scaling, SMOTE, model evaluation",
        skill_style,
    ),
    Paragraph("<b>Tools:</b> Advanced Excel, Power BI, Microsoft Office", skill_style),
    Paragraph("<b>Languages:</b> English and Vietnamese (bilingual)", skill_style),
]

doc.build(story, onFirstPage=draw_page, onLaterPages=draw_page)
print(OUTPUT)
