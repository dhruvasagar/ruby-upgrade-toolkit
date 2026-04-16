---
description: Apply all upgrade fixes — version pins, gem updates, code changes, RSpec fixes, and RuboCop fixes. Usage: /ruby-upgrade-toolkit:fix ruby:X.Y.Z [rails:X.Y] [scope:path]
argument-hint: "ruby:X.Y.Z [rails:X.Y] [scope:path]"
---

Parse the arguments provided by the user:
- `ruby:X.Y.Z` — required. The target Ruby version.
- `rails:X.Y` — optional. When provided, also applies Rails upgrade fixes.
- `scope:path` — optional. Restricts code fixes to the given file or directory (e.g. `scope:app/models/user.rb` or `scope:app/controllers/`). Gem and version pin changes always apply to the whole project regardless of scope.

Current versions are auto-detected.

Use the `ruby-upgrade-toolkit:fix` skill to apply the fixes.
