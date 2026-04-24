---
description: Manage project-specific custom upgrade rules — gem pins, gem swaps, private-source substitutions (Rails LTS, Sidekiq Pro), verification gates (Brakeman, Reek), policy overrides, and more. Subcommands: init, validate, list, show, add, remove, disable, enable, explain.
argument-hint: "[init | validate | list | show <id> | add <type> | remove <id> | disable <id> | enable <id> | explain]"
---

Parse the first argument as the subcommand:

- `init` — create a starter `.ruby-upgrade-toolkit/rules.yml` with one commented example of each rule type
- `validate` — schema-check the existing rules file; exits non-zero on error
- `list [--all]` — show active rules; `--all` includes disabled
- `show <id>` — detailed view of one rule with its computed effects and preflight status
- `add <type>` — interactive Q&A authoring for a new rule; `<type>` is one of `gem-constraint`, `gem-swap`, `target-substitute`, `code-transform`, `phase-inject`, `verification-gate`, `policy-override`, `intermediate-pin`
- `remove <id>` — delete a rule after a diff preview and confirmation
- `disable <id>` / `enable <id>` — toggle the `enabled` flag without deleting
- `explain` — dry-run: show which rules will fire in the current project and which will no-op, with reasons

If no subcommand is given, default to `list`.

Read `$CLAUDE_PLUGIN_ROOT/skills/rules/SKILL.md` and follow its instructions completely, passing the parsed subcommand and arguments.
