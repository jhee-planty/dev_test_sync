# Batch 4: Document & Utility Skills Analysis

Analysis of 6 foundational document/utility skills from `.claude/skills/`. All skills are proprietary with LICENSE.txt. None exist in `shared-skills/` directory.

---

## 1. DOCX Skill

**Location:** `/sessions/trusting-zen-darwin/mnt/.claude/skills/docx/SKILL.md`

### Basic Info
- **Name & Purpose:** Word document creation, editing, and manipulation. Comprehensive skill for handling .docx files as ZIP archives containing XML — covers reading, creating with docx-js, and editing via unpack/edit/pack workflow.
- **Line Count:** 590 lines
- **Trigger Keywords:** "Word doc", ".docx", professional documents with formatting (TOC, headings, page numbers), letterheads, extraction, reorganization, tracked changes, comments

### Key Sections
| Section | Line Range | Notes |
|---------|-----------|-------|
| Overview | 7-11 | Explains .docx structure as ZIP+XML |
| Quick Reference Table | 13-19 | Task→Approach mapping |
| Converting .doc to .docx | 21-27 | LibreOffice soffice.py |
| Reading Content | 29-37 | pandoc + XML unpacking |
| Converting to Images | 39-44 | PDF→images via LibreOffice |
| Accepting Tracked Changes | 46-52 | accept_changes.py script |
| Creating New Documents | 56-73 | docx-js setup imports |
| Validation | 74-78 | validate.py script |
| Page Size | 80-114 | **CRITICAL:** A4 default, US Letter dims in DXA |
| Styles (Headings) | 116-140 | Override built-in with exact IDs (Heading1, Heading2) |
| Lists | 142-174 | **CRITICAL:** Never use unicode bullets, use LevelFormat.BULLET |
| Tables | 176-222 | **CRITICAL:** Dual widths (table + cells), use WidthType.DXA not PERCENTAGE |
| Images | 223-235 | **CRITICAL:** type parameter required (png/jpg/etc) |
| Page Breaks | 237-245 | Must be inside Paragraph |
| Hyperlinks | 247-268 | External + internal (bookmarks) |
| Footnotes | 270-289 | footnotes object + FootnoteReferenceRun |
| Tab Stops | 291-317 | Right-align + dot leaders |
| Multi-Column Layouts | 319-350 | Equal-width or custom columns, SectionType.NEXT_COLUMN breaks |
| Table of Contents | 352-357 | **CRITICAL:** HeadingLevel only, no custom styles |
| Headers/Footers | 359-376 | Header/Footer objects with PageNumber.CURRENT |
| Critical Rules Summary | 378-395 | **15 explicit CRITICAL rules** |
| Editing: Step 1 Unpack | 400-406 | unpack.py, merge runs, smart quotes |
| Editing: Step 2 Edit XML | 408-434 | Smart quotes (&#x2019;, &#x201C;, etc), comment.py, author="Claude" |
| Editing: Step 3 Pack | 436-441 | pack.py with validation, auto-repair |
| Common Pitfalls | 449-452 | Replace whole `<w:r>`, preserve `<w:rPr>` |
| XML Reference | 456-582 | Comprehensive XML patterns (tracked changes, comments, images) |
| Dependencies | 585-590 | pandoc, docx npm, LibreOffice, Poppler |

### Cross-References
- **Relies on:** LibreOffice (scripts/office/soffice.py), pandoc, docx npm library, Python validation/packing scripts
- **Related skills:** PPTX (similar Office architecture), PDF (format conversion target)
- **External references:** None to other Cowork skills

### Trigger Conditions
- Whenever user mentions "Word doc", ".docx", "document"
- Requests for formatted documents: reports, memos, letters, templates
- Any document operations: extract, edit, insert images, find-replace, tracked changes, conversion
- Deliverable must be .docx

### Potential Issues

#### Outdated References
- None identified. docx-js library API appears current.

#### Missing Information / Gaps
1. **No guidance on document templates** — User can't easily start from existing corporate templates (only from scratch)
2. **Limited merge/batch operations** — No mention of combining multiple .docx files
3. **Comments workflow unclear** — `comment.py` is mentioned but the full workflow (run script → edit markers → pack) feels disjointed
4. **No mention of compatibility** — What does this produce in older Office versions? Google Docs compatibility?
5. **Smart quotes implementation** — The XML entities table is helpful, but no easy copy-paste reference for common punctuation

#### Unclear Instructions
1. **Landscape orientation explanation (lines 106-114)** — The note "docx-js swaps width/height internally" is confusing. Why pass portrait dims for landscape? This feels backwards and needs a diagram or worked example.
2. **Unpack/pack dependencies** — Not clear if all 3 steps (unpack, edit, pack) are REQUIRED in sequence, or if you can skip validation or use `--merge-runs false`
3. **XML naming in tracked changes** — The distinction between `<w:delText>` and `<w:delInstrText>` (line 480) is mentioned but not explained — when should each be used?

#### Structure Observations
- **Well-organized:** Clear separation between Create, Edit, and XML Reference sections
- **Comprehensive:** Covers 90% of docx use cases with code examples
- **Highly technical:** Requires understanding XML structure, DXA units, and Office schema
- **CRITICAL rules heavily marked:** 15 explicit CRITICAL callouts show pain points from past implementations
- **Strength:** Excellent XML reference section with real patterns (tracked changes, comments, images nested correctly)
- **Weakness:** Assumes users are comfortable with XML and Python scripting

---

## 2. XLSX Skill

**Location:** `/sessions/trusting-zen-darwin/mnt/.claude/skills/xlsx/SKILL.md`

### Basic Info
- **Name & Purpose:** Spreadsheet creation, editing, and analysis. Handles .xlsx, .xlsm, .csv, .tsv files. Covers both data analysis (pandas) and formulas/formatting (openpyxl), with emphasis on dynamic formulas over hardcoded values.
- **Line Count:** 291 lines
- **Trigger Keywords:** Spreadsheet file operations, data cleaning, formula building, charting, CSV/TSV conversion, deliverable must be .xlsx (not Google Sheets or HTML reports)

### Key Sections
| Section | Line Range | Notes |
|---------|-----------|-------|
| Requirements for Outputs | 7-21 | Professional font, ZERO formula errors, preserve templates |
| Financial Models Color Coding | 24-33 | Industry-standard conventions (blue=input, black=formula, green=cross-sheet, red=external, yellow=assumptions) |
| Number Formatting Standards | 35-42 | Years as text, currency with units, zeros as "-", percentages 0.0%, multiples as 0.0x |
| Formula Construction Rules | 44-64 | Assumptions in separate cells, error prevention, source documentation |
| Overview | 68-70 | Different tools for different tasks |
| Important Requirements | 72-74 | LibreOffice for formula recalc via scripts/recalc.py |
| Data Analysis with Pandas | 76-95 | pd.read_excel(), analysis, write |
| CRITICAL: Formulas Not Hardcoded | 99-131 | **Major emphasis:** Always use Excel formulas, not Python calculations (multiple WRONG/CORRECT examples) |
| Common Workflow | 132-150 | 6-step process ending with scripts/recalc.py |
| Creating New Excel Files | 151-178 | openpyxl Workbook, formulas, formatting |
| Editing Existing Files | 180-205 | load_workbook, cell modification, multi-sheet |
| Recalculating Formulas | 207-226 | scripts/recalc.py with timeout, returns JSON error details |
| Formula Verification Checklist | 227-248 | 12-point checklist (NaN handling, column mapping, division by zero, etc) |
| Interpreting scripts/recalc.py Output | 249-263 | JSON structure with error_summary |
| Best Practices | 265-292 | Library selection, openpyxl gotchas (data_only=True loses formulas), pandas dtype handling |

### Cross-References
- **Relies on:** openpyxl library, pandas library, LibreOffice (scripts/recalc.py), Python
- **Related skills:** DOCX, PDF (for report generation), pptx (for data visualization)
- **Cross-skill notes:** Mentions "Do NOT trigger when...deliverable is HTML report or database pipeline"

### Trigger Conditions
- Spreadsheet file is primary input/output
- Any mention of .xlsx, .xlsm, .csv, .tsv by name/path (even casual references)
- Data cleaning, restructuring messy tabular data
- Formula building, charting, formatting
- Deliverable MUST be spreadsheet file (not Google Sheets, not HTML, not database)

### Potential Issues

#### Outdated References
- None identified. openpyxl and pandas are actively maintained.

#### Missing Information / Gaps
1. **No guidance on data validation** — How to add dropdown lists, constraints, or conditional validation?
2. **No chart creation examples** — Formulas are covered extensively but chart creation (bar, pie, scatter) is not mentioned
3. **No pivot table support** — How to create or manipulate pivot tables?
4. **CSV/TSV handling light** — Mentioned in intro but no specific workflow shown
5. **Large file handling vague** — "For large files use read_only=True" (line 275) but no threshold given
6. **Merge cells not covered** — Complex formatting with merged cells not addressed

#### Unclear Instructions
1. **scripts/recalc.py timeout parameter** — Line 213 shows example `python scripts/recalc.py output.xlsx 30` but no guidance on what timeout is appropriate or what happens if timeout expires
2. **Error recovery workflow** — When recalc.py returns errors (line 141-150), instructions say "fix the identified errors and recalculate again" but don't explain how to FIX them in code
3. **data_only warning (line 274-275)** — "If opened with data_only=True and saved, formulas are replaced with values and permanently lost" — this is critical but buried in Best Practices; should be in Requirements

#### Structure Observations
- **Well-organized:** Clear Requirements section upfront, then tool selection, then workflows
- **Formula-focused:** Extensive emphasis on the WRONG pattern (hardcoding) vs CORRECT pattern (using formulas)
- **Best Practices solid:** Color coding standards are industry-standard and well-explained
- **Strength:** Excellent emphasis on zero-error deliverables and formula construction rules
- **Weakness:** Assumes openpyxl/pandas knowledge; limited guidance on UI-based Excel features (charts, pivot tables, validation)

---

## 3. PPTX Skill

**Location:** `/sessions/trusting-zen-darwin/mnt/.claude/skills/pptx/SKILL.md`

### Basic Info
- **Name & Purpose:** PowerPoint/slide deck creation, editing, and extraction. Covers both reading content (markitdown) and creating from scratch (pptxgenjs) or templates. Extensive section on design best practices and visual QA.
- **Line Count:** 231 lines
- **Trigger Keywords:** "deck", "slides", "presentation", .pptx files, pitch decks, any mention of slides regardless of downstream use

### Key Sections
| Section | Line Range | Notes |
|---------|-----------|-------|
| Quick Reference | 9-15 | 3 main workflows (read, edit template, create scratch) |
| Reading Content | 19-30 | markitdown extraction, thumbnail.py, raw XML unpacking |
| Editing Workflow | 34-40 | References editing.md (external file) |
| Creating from Scratch | 43-48 | References pptxgenjs.md (external file) |
| Design Ideas: Before Starting | 51-61 | Color palette strategy (60-70% dominance, 1-2 supporting, 1 accent) |
| Color Palettes | 62-77 | 10 pre-built palettes with hex codes (Midnight, Forest, Coral, Ocean, etc) |
| For Each Slide | 79-96 | Visual elements required, layout options, data display ideas |
| Typography | 98-119 | Font pairings, size ranges (36-44pt titles, 14-16pt body) |
| Spacing | 120-125 | 0.5" minimum margins, 0.3-0.5" between blocks |
| Avoid (Common Mistakes) | 126-137 | **11 explicit DON'Ts** (don't repeat layouts, center body text, use blue, forget padding, etc) |
| QA (Required) | 141-205 | Content QA (markitdown check), Visual QA (subagent inspection), verification loop |
| Converting to Images | 208-221 | soffice.py → PDF → pdftoppm for slide inspection |
| Dependencies | 225-231 | markitdown, Pillow, pptxgenjs npm, LibreOffice, Poppler |

### Cross-References
- **Relies on:** External files `editing.md` and `pptxgenjs.md` (not provided in this analysis)
- **Related skills:** PDF (output format), DOCX (similar Office architecture)
- **Process references:** Uses subagents for visual QA (line 165) — expects delegated inspection

### Trigger Conditions
- Any mention of "deck", "slides", "presentation", .pptx file
- Creating slide decks, pitch decks, presentations
- Extracting/parsing content from .pptx (even if used elsewhere)
- Editing, modifying, updating presentations
- Combining/splitting slides

### Potential Issues

#### Outdated References
- **External file references:** Lines 14, 36, 45 reference `editing.md` and `pptxgenjs.md` which are NOT included in the SKILL.md being analyzed. This is a **critical structural issue** — the skill file should be self-contained.

#### Missing Information / Gaps
1. **No actual pptxgenjs code examples** — Entire creation workflow delegated to pptxgenjs.md
2. **No editing workflow specifics** — editing.md is referenced but not provided
3. **No animation/transition guidance** — Nothing on timing, animation effects, slide transitions
4. **No speaker notes handling** — Comments/notes mentioned nowhere
5. **No accessibility guidance** — No alt text for images, no contrast requirements beyond color palette

#### Unclear Instructions
1. **Subagent QA (line 165)** — "Use subagents — even for 2-3 slides" — but setup-cowork skill is designed for onboarding, not mid-workflow delegation. How is this integration supposed to work?
2. **grep check for placeholders (line 158)** — `grep -iE "\bx{3,}\b|lorem|ipsum|\bTODO..."` — This is helpful but very specific; what if placeholder text doesn't match these patterns?
3. **Verification loop (line 196-204)** — Requires "at least one fix-and-verify cycle" but doesn't define what counts as "success" (zero issues found vs. acceptable issues)

#### Structure Observations
- **Design-forward:** Unusual for a technical skill — extensive design best practices (color, typography, spacing) before any code
- **Lean on code examples:** Only QuickReference and Converting to Images show actual commands; creation/editing delegated to external files
- **QA as core process:** Dedicates ~65 lines (27% of document) to QA, treating it as integral
- **Strength:** Design guidance is professional and specific (10 color palettes, font pairings, explicit "avoid" list)
- **Weakness:** Incomplete without editing.md and pptxgenjs.md files; external dependencies create brittleness

---

## 4. PDF Skill

**Location:** `/sessions/trusting-zen-darwin/mnt/.claude/skills/pdf/SKILL.md`

### Basic Info
- **Name & Purpose:** PDF processing for reading, extracting, merging, splitting, rotating, watermarking, encrypting, and creating PDFs. Covers both Python libraries (pypdf, pdfplumber, reportlab) and command-line tools (pdftotext, qpdf, pdftk).
- **Line Count:** 314 lines
- **Trigger Keywords:** .pdf files, reading/extracting text/tables, merging/splitting, forms, watermarks, encryption, OCR

### Key Sections
| Section | Line Range | Notes |
|---------|-----------|-------|
| Overview | 7-11 | Mentions REFERENCE.md and FORMS.md (external) |
| Quick Start | 13-26 | PdfReader basics |
| pypdf: Merge PDFs | 30-44 | PdfWriter + iterate pages |
| pypdf: Split PDF | 46-54 | One page per file loop |
| pypdf: Extract Metadata | 56-65 | Reader.metadata (title, author, subject, creator) |
| pypdf: Rotate Pages | 67-78 | page.rotate(90) |
| pdfplumber: Extract Text | 81-90 | page.extract_text() with layout preservation |
| pdfplumber: Extract Tables | 91-100 | page.extract_tables() |
| pdfplumber: Advanced Tables | 102-119 | pandas DataFrame conversion to Excel |
| reportlab: Basic Creation | 123-140 | Canvas for simple text/lines |
| reportlab: Multiple Pages | 142-167 | SimpleDocTemplate + Platypus (Paragraph, Spacer, PageBreak) |
| Subscripts/Superscripts | 169-187 | **CRITICAL:** Never use Unicode subscripts (₀₁₂), use `<sub>` and `<super>` tags in Paragraph |
| Command-Line Tools | 189-230 | pdftotext, qpdf, pdftk |
| Common Tasks | 232-294 | OCR, watermarks, extract images, password protection |
| Quick Reference Table | 296-307 | Task→tool mapping |
| Next Steps | 309-315 | References REFERENCE.md and FORMS.md |

### Cross-References
- **Relies on:** pypdf, pdfplumber, reportlab (Python), pdftotext/qpdf/pdftk (CLI), pytesseract (OCR)
- **Related skills:** DOCX (conversion target), PPTX (conversion source)
- **External references:** REFERENCE.md (advanced pypdfium2), FORMS.md (form filling)

### Trigger Conditions
- Any .pdf file operations
- Reading/extracting text/tables
- Merging/splitting/rotating pages
- Watermarks, encryption/decryption
- Form filling
- OCR on scanned PDFs

### Potential Issues

#### Outdated References
- **External file references:** Lines 11, 307, 313 reference REFERENCE.md and FORMS.md which are NOT provided. FORMS.md is mentioned as the "must-read" for form filling (line 314) but unavailable.

#### Missing Information / Gaps
1. **Form filling incomplete** — Critical feature (mentioned 3 times) but deferred entirely to FORMS.md
2. **No advanced layout extraction** — pdfplumber covers tables but not multi-column text, headers/footers, or element positioning
3. **No digital signature guidance** — Mentioned in overview but no examples
4. **Compression/optimization not covered** — How to reduce file size, remove metadata?
5. **No batch operations** — All examples are single-file; how to batch process 100 PDFs?

#### Unclear Instructions
1. **reportlab SuperScript/Subscript warning (line 169-187)** — Extensive warning about Unicode glyphs but the solution `<sub>` and `<super>` tags only works inside Paragraph objects, not Canvas. Canvas users are left without guidance.
2. **OCR workflow (line 233-250)** — Requires pdf2image + pytesseract but no installation instructions or compatibility warnings (pytesseract needs Tesseract binary)
3. **qpdf split syntax** — Line 209-210 shows splitting by page range but the syntax `--pages . 1-5` is cryptic — what does the dot mean?

#### Structure Observations
- **Library-focused:** Organized by library/tool rather than task (pypdf section, then pdfplumber, then reportlab)
- **Heavy on code examples:** Every operation has Python code examples
- **Command-line tools included:** Unusual to mix Python + CLI in same skill
- **External dependencies heavy:** At least 2 critical workflows (forms, reference) deferred to external files
- **Strength:** Comprehensive coverage of common tasks with ready-to-use code
- **Weakness:** Incomplete without FORMS.md and REFERENCE.md; OCR is complex but under-documented

---

## 5. Study-Material-Creator Skill

**Location:** `/sessions/trusting-zen-darwin/mnt/.claude/skills/study-material-creator/SKILL.md`

### Basic Info
- **Name & Purpose:** Korean-language skill for generating study materials from notes/textbooks/keywords. Creates markdown with glossaries, analogies, comparison tables, and practice questions. Flexible structure based on subject type (natural science, humanities, math, tech, language).
- **Line Count:** 201 lines
- **Trigger Keywords:** "학습 자료 만들어줘", "공부 자료 정리", "노트 정리", "마크다운으로 정리", "예상 문제", "초보자도 이해", "시험 대비 자료"

### Key Sections
| Section | Line Range | Notes |
|---------|-----------|-------|
| Overview (개요) | 19-26 | 3 core principles: content-driven structure, term-friendly, images supplementary |
| Step 1: Input Analysis | 30-60 | Type detection (natural science, humanities, math, tech, language) with feature tables |
| Step 1-2: Term Difficulty | 46-51 | Light terms → no glossary; heavy terms → glossary upfront |
| Step 1-3: Image Necessity | 52-60 | Decide if images help (microscope photos yes, math formulas no) |
| Step 2: Study Material Generation | 63-114 | Structure design with subject-specific component selection |
| Common Elements Table | 70-89 | Components mapped to 5 subject types with ◎/○/△/× priority |
| Step 2-2: Markdown Writing Principles | 92-101 | Glossary upfront, analogies/etymology, comparison tables, practice problems with answers |
| Step 2-3: File Output | 102-114 | Folder structure: `{topic}_학습자료/` with markdown + images/ subfolder |
| Step 3: Image Collection | 117-196 | Strategy decision tree (needed?→provided?→environment?→success?) |
| Image Collection Environments | 144-181 | 3 environments (Claude.ai chat, Cowork Windows-MCP, Claude Code) with specific workflows |
| Recommended Image Sources | 183-192 | Wikimedia Commons, BCC Bioscience, Unsplash, OpenStax |
| Caveats | 196-202 | Don't modify source accuracy, target beginner comprehension, prioritize understanding over memorization |

### Cross-References
- **Relies on:** image_search tool, web_search tool, Playwright/curl for downloads
- **Related skills:** No explicit cross-references to other skills
- **Environment-specific:** References Claude.ai, Cowork (Windows-MCP), Claude Code

### Trigger Conditions
- "학습 자료 만들어줘", "공부 자료 정리", "노트 정리"
- Requests for markdown formatting with term explanations
- "초보자도 이해할 수 있게"
- "예상 문제 포함"
- Study notes, textbook content, keyword lists
- Any subject (science, history, math, programming)

### Potential Issues

#### Outdated References
- **Language barrier:** Skill is entirely in Korean but deployed in English-language Cowork environment (system messages are in English). Will skill selector work correctly?

#### Missing Information / Gaps
1. **No file size guidance** — When is a study material "too long"? Single file vs. multiple?
2. **No math formula support** — How to represent mathematical notation in markdown? LaTeX? Unicode? Nothing specified.
3. **No version control mentioned** — If user asks for revisions, how to track/manage multiple iterations?
4. **Bibliography/citation guidance missing** — How to cite sources in study materials?
5. **No assessment rubric** — How to verify if the generated material meets the user's learning needs?

#### Unclear Instructions
1. **"Component selection" (line 68)** — The decision process for which elements to include is vague. Table shows ◎/○/△/× but no algorithm for choosing. Does ◎ mean "must include" or "typically include"?
2. **Image environment decision (line 132-137)** — Decision tree for "현재 환경에서 이미지 수집이 가능한가?" but how does the skill auto-detect environment? No explicit check shown.
3. **Windows-MCP example (line 157-166)** — PowerShell snippet shows Invoke-WebRequest with retry logic "3~5초로 늘려" but no code example. Unclear if skill should implement this or ask user.
4. **File path discrepancy (line 152, 168, 181)** — 3 different output paths suggested for 3 environments — this creates confusion about where final files live

#### Structure Observations
- **Language choice unusual:** Entire skill in Korean despite English-language system context
- **Environment-aware:** Explicitly handles 3 different deployment contexts (Claude.ai, Cowork, Claude Code)
- **Flexible framework:** Doesn't force one template; adjusts to subject type
- **Image handling pragmatic:** Decision tree acknowledges "sometimes images aren't worth it" and defaults to text
- **Strength:** Deep pedagogical thinking (analogies, etymology, understanding over memorization)
- **Weakness:** File path confusion across environments; language barrier in English system; component selection algorithm vague

---

## 6. Setup-Cowork Skill

**Location:** `/sessions/trusting-zen-darwin/mnt/.claude/skills/setup-cowork/SKILL.md`

### Basic Info
- **Name & Purpose:** Onboarding flow for Cowork setup. 5-step workflow: role picker → plugin install → try a skill → connectors → wrap-up. Guides users through configuring Cowork with plugins, skills, and tool integrations.
- **Line Count:** 47 lines
- **Trigger Keywords:** First-time Cowork setup, onboarding

### Key Sections
| Section | Line Range | Notes |
|---------|-----------|-------|
| Opening | 6-8 | Frame Cowork as autonomous task handler (email, docs, reports) |
| Step 1: Role Picker | 10-14 | Ask role, call role picker tool (don't list roles yourself) |
| Step 2: Install Plugin | 16-22 | Search marketplace for role, suggest best match plugin |
| Step 3: Try a Skill | 24-30 | After plugin installed, explain skills + wait for user to try one. Return to setup after skill completes. |
| Step 4: Connectors | 32-36 | Brief explanation of connectors (plug in real tools), search registry by role, suggest top 2-3 |
| Step 5: Wrap | 38-40 | Confirm setup complete, dismiss with forward reference to `/` command |
| Ground Rules | 42-48 | One step at a time, skips OK, keep messages short, expect skill invocations mid-flow |

### Cross-References
- **Relies on:** Role picker tool, plugin marketplace search, connector registry search, skill invocation system
- **Related skills:** All other skills (this is the entry point that presents them)
- **System dependencies:** Plugin system, connector system, skill invocation system

### Trigger Conditions
- First-time Cowork user setup
- Explicitly called setup-cowork via `/` command

### Potential Issues

#### Outdated References
- None identified. Framework-level references are stable.

#### Missing Information / Gaps
1. **No fallback for role picker dismissal** — Line 18 says "if dismissed, suggest productivity plugin" but no example text shown
2. **No error handling** — What if plugin marketplace search returns nothing? What if user's role isn't in the picker?
3. **No timeout/skip guidance** — If user abandons mid-setup, what's the recovery? (Probably restart, but not stated)
4. **No success metrics** — How do you know setup was successful? Just "they connected something"?
5. **No troubleshooting** — What if plugin install fails or connector authentication fails?

#### Unclear Instructions
1. **"Don't list roles yourself" (line 14)** — Why is this important? Creates better UX presumably, but no rationale.
2. **"help them with it briefly" (line 30)** — How long is "briefly"? One turn? Until completion? Unclear boundary.
3. **"search connector registry using their role as the keyword" (line 36)** — Does this mean search for connectors tagged with that role? The search API isn't specified.
4. **"suggest connectors...with top 2-3 UUIDs" (line 36)** — Why 2-3? Why not 1? Why not 5? No rationale.

#### Structure Observations
- **Linear 5-step flow:** Very structured, one-at-a-time progression
- **Minimal content:** Only 47 lines; heavily condensed
- **Framework-level skill:** Doesn't do substantive work; orchestrates other systems
- **Ground rules clarify edge cases:** "Skill invocations mid-flow expected" shows understanding of user behavior
- **Strength:** Clear linear flow, acknowledges legitimate skips, keeps momentum short
- **Weakness:** Under-specified for error cases; lacks examples and rationale for design decisions

---

## Cross-Skill Observations

### Comparison: Document Skills (DOCX, XLSX, PPTX, PDF)

| Aspect | DOCX | XLSX | PPTX | PDF |
|--------|------|------|------|-----|
| **Line Count** | 590 | 291 | 231 | 314 |
| **Complexity** | Very High (XML) | High (Formulas) | Medium-High (Design) | High (Multiple libs) |
| **External Deps** | editing.md (implied) | None | editing.md, pptxgenjs.md | FORMS.md, REFERENCE.md |
| **Code Examples** | Extensive | Extensive | Minimal | Extensive |
| **Design Guidance** | None | Industry standards | Professional (colors, fonts) | None |
| **QA Process** | Validation script | Recalc script | Subagent inspection | None mentioned |

### Comparison: Utility Skills (Study-Material-Creator, Setup-Cowork)

| Aspect | Study-Material-Creator | Setup-Cowork |
|--------|------|------|
| **Line Count** | 201 | 47 |
| **Scope** | Educational content generation | Onboarding flow |
| **Subject-Aware** | Yes (5 types) | No (generic setup) |
| **Environment-Aware** | Yes (3 environments) | No |
| **Language** | Korean | English |
| **Dependencies** | image_search, web_search | plugin/connector registry |

### Cross-Skill Patterns

1. **External file references are brittle:**
   - PPTX references editing.md, pptxgenjs.md (not provided)
   - PDF references FORMS.md, REFERENCE.md (not provided)
   - Creates documentation fragmentation

2. **Formula/Calculation emphasis:**
   - XLSX: Extensive "never hardcode" emphasis with multiple examples
   - Others: No similar calculations

3. **Design as core process:**
   - PPTX: 27% of content is design best practices
   - Others: No design guidance

4. **QA/Verification builtin:**
   - DOCX: validate.py script
   - XLSX: scripts/recalc.py mandatory
   - PPTX: Subagent visual QA
   - PDF: No QA process mentioned

5. **Library variety:**
   - PDF: 3+ libraries (pypdf, pdfplumber, reportlab) + CLI tools
   - XLSX: 2 libraries (pandas, openpyxl) + LibreOffice
   - DOCX: 1 library (docx-js) + LibreOffice
   - PPTX: 1 library (pptxgenjs) + external editors

---

## Summary: Quality Assessment

### Strengths
1. **DOCX & XLSX**: Comprehensive coverage with industry standards, extensive code examples, explicit critical rules
2. **PDF**: Multiple library options with both Python and CLI approaches
3. **PPTX**: Professional design guidance, color palettes, typography pairings
4. **Study-Material-Creator**: Flexible framework, environment-aware, pedagogically thoughtful
5. **Setup-Cowork**: Clear linear flow, acknowledges real user behavior

### Weaknesses
1. **External dependencies**: PPTX and PDF reference external files (editing.md, pptxgenjs.md, FORMS.md, REFERENCE.md) not provided
2. **Incomplete workflows**: PDF form filling entirely deferred; PPTX creation/editing delegated
3. **Error handling sparse**: Most skills assume happy path; limited guidance for failures
4. **Accessibility gaps**: No alt text, no screen reader guidance, no internationalization except Study-Material-Creator
5. **Large file handling**: XLSX mentions best practices but not thresholds; PPTX/PDF don't address large decks/files
6. **Feature gaps**: Charts (XLSX), animations (PPTX), OCR setup (PDF), batch operations (all)

### Documentation Quality Ranking
1. **XLSX** — Most complete, best structured, industry standards embedded
2. **DOCX** — Comprehensive, good XML reference, many critical rules properly highlighted
3. **PDF** — Good coverage but incomplete (FORMS.md, REFERENCE.md missing)
4. **PPTX** — Good design guidance but incomplete (editing.md, pptxgenjs.md missing)
5. **Study-Material-Creator** — Well-conceived but language/environment path confusion
6. **Setup-Cowork** — Clear but under-specified (no error cases, no examples)

---

## Recommendations for Improvement

1. **Consolidate external files**: editing.md, pptxgenjs.md, FORMS.md, REFERENCE.md should be integrated or clearly marked as prerequisites
2. **Add error handling sections**: All skills should cover "what if it fails?"
3. **Include batch/large-file guidance**: How to handle 100 files, 10MB files, etc.
4. **Standardize QA processes**: All output skills should define verification
5. **Add accessibility guidance**: alt text for images, contrast for colors, captions for audio
6. **Clarify environment detection**: Study-Material-Creator's 3-environment handling is clever but brittle; formalize detection
7. **Include troubleshooting**: Common errors and fixes for each skill
8. **Add examples with edge cases**: Not just happy path; show zip files, corrupted files, unsupported formats

