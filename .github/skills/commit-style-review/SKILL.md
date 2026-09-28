---
name: erik-review
description: 'Use when reviewing a commit, pull request, or change set to summarize edits to comments, documentation, variable and function naming, and code style, and to extract a reusable reviewer rubric.'
argument-hint: '[commit, pull request, or change set]'
---

# Commit Style Review

Analyze how a change alters the codebase's communication and coding conventions. Produce an evidence-based summary that can inform a reusable review rubric. Do not assume that every changed pattern is intentional or worth adopting.

## Procedure

1. Identify the target commit or change set and its baseline, normally the first parent of a commit. Check the worktree and do not overwrite or revert unrelated user changes.
2. Read applicable repository guidance (`copilot-instructions.md`, `AGENTS.md`, and file instructions) before judging style. Inspect recent neighboring changes only as needed to distinguish current conventions from legacy code.
3. Inspect the complete diff and read nearby before-and-after context for representative edits. Include affected tests and documentation when present. Separate behavior changes from changes that are primarily editorial or stylistic.
4. Summarize relevant patterns under these categories:
   - **Comments:** changes to purpose, rationale, language, section markers, and whether comments stay accurate after implementation changes.
   - **Documentation:** scope and completeness of README/API/setup changes, including version requirements, migration notes, and new behavior that is not documented.
   - **Naming:** changes to variables, parameters, functions, properties, constants, casing, abbreviations, and public API names. Note consistency with surrounding code.
   - **Style:** formatting, language idioms, error handling, literals, access levels, and repeated structural conventions.
5. For each claimed pattern, give a concise before/after example with a file reference. Distinguish a repeated convention from a one-off change; a single commit is evidence about that commit, not proof of a repository-wide standard.
6. Verify suspicious or consequential observations against the actual language and nearby call sites. Look for typos, lost diagnostic detail or localization, mismatched event/data shapes, cross-language idiom mistakes, API visibility changes, and missing tests. Report confirmed defects separately from stylistic observations, and label uncertain concerns as such.
7. End with a short set of proposed reviewer rules phrased as checks another reviewer can apply. Preserve useful intent, but do not recommend copying accidental inconsistencies or defects.

## mlapp checks

When the mlapp is changed, review the corresponding exported source and ensure that all relevant style and documentation conventions are followed. If changes are made, explicitly alert user to the modifications and the need to update the corresponding mlapp file.

- Review the corresponding `*_exported.m` for App Designer changes; `.mlapp` files are binary and are not the source to inspect directly. Note whether the exported source and App Designer file are both updated as required by the repository workflow.
- Check the documented naming conventions: PascalCase for GUI elements and classes, camelCase for functions, methods, and local variables, and SCREAMING_CASE for constants. Prefer the documented convention for new or renamed identifiers; do not treat unchanged legacy names as regressions introduced by the commit.
- Check for the `%-----------------------------------------------------------------%` divider before each function, as required by the repository guidance.
- Keep comments and documentation in the language used by the surrounding module, commonly Portuguese. For data/schema compatibility code, check that comments explain what older saved data needs and that the migration is implemented and tested.
- Check whether meaningful behavior or compatibility changes also update relevant documentation and tests. A recent commit can establish current practice, but it does not replace the repository's written guidance.

## Output

Use a concise report with:

- **Commit overview:** the behavioral scope and the files or layers affected.
- **Observed editorial/style changes:** grouped by comments, documentation, naming, and style; cite representative before/after examples.
- **Review concerns:** concrete regressions, inconsistencies, or missing verification, ordered by impact and supported by file references.
- **Reusable review checks:** a small checklist distilled from the evidence, clearly separating confirmed project conventions from suggestions inferred from this change.
- **Coverage limits:** mention unreviewed areas or missing tests when they affect confidence.

Avoid treating formatting churn or broad renames as inherently beneficial. Do not modify the reviewed change unless implementation work is separately requested.