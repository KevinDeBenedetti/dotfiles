---
name: research
description: Check a question against primary sources - official docs, source code, specs, first-party APIs - and report each finding with its source. Use when a claim about an external tool, library or API must be verified, when options have to be compared before a decision, or when the owner asks to research a topic.
---

# Research

<!-- Adapted from mattpocock/skills (MIT). Notice: config/skills/NOTICE.md in
     the dotfiles repository. Edit it there only. -->

Answer the question from the source that owns the fact.

1. Write the question down, and what would count as an answer.
2. Read **primary sources**: the tool's own documentation for the version in
   use, its source code, the spec, the output of the command itself
   (`--help`, `--version`). A blog post or a forum answer is a lead to follow
   back to its source, never the citation.
3. Check the version: read which one the project pins before reading the
   docs for it.
4. Report each finding with its source (a URL that answers, a file and line,
   the command that printed it), and say plainly what you could not confirm.

With sub-agents, hand the reading to one on a fresh context and keep working;
verify what it brings back before relying on it.

The findings go in the chat. Write them to a file only when the owner asks,
where the repository already keeps such notes.
