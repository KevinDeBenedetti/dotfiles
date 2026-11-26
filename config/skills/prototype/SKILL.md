---
name: prototype
description: Build a throwaway prototype that answers one design question - whether a state model or some logic feels right, or what a UI should look like. Use when the owner asks for a prototype, a spike or a proof of concept, or when a decision cannot be settled by discussion.
---

# Prototype

<!-- Adapted from mattpocock/skills (MIT). Notice: config/skills/NOTICE.md in
     the dotfiles repository. Edit it there only. -->

A prototype is throwaway code that answers one question. Write the question
down first, in one sentence: it decides the shape.

| Question                                    | Build                                                                                                   |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| does this logic or state model feel right?  | one self-contained file the owner can run or open, that pushes the model through the hard cases         |
| what should this look like?                 | a few clearly different variants of one screen, switchable without a rebuild                            |

Ask when the question could be either and the owner is there; otherwise take
the one the surrounding code suggests and say so at the top of the prototype.

## Rules

1. **Marked as throwaway.** Next to the code it explores, under a name that
   says prototype, following the project's own layout.
2. **One command to run**, or one file to open. Give that command.
3. **State in memory.** When storage is the question, a scratch file or
   database whose name says it can be wiped.
4. **No polish**: no tests, no abstraction, no error handling beyond what
   makes it run.
5. **Show the state** after every action or variant switch, so the owner sees
   what changed.

## Close

Done when the owner has run it and the question has an answer. Then:

- state the verdict and the question it settled, for the issue or the commit
  message;
- move the validated decision into the real code as its own piece of work;
- delete the prototype, or hand the owner the commands that keep it on a
  branch of its own (`git-workflow`), out of the main branch.
