# Working with the owner

- Always prompt for input: when there is a decision to make or a next step to choose, ask with
  the question dialog (AskUserQuestion) instead of ending a reply with an open question in prose
  or picking on your own.
- Auto-merge by default: when you open a pull request in this repository, enable auto-merge on
  it right away, with a merge commit. If GitHub refuses (the repository's "Allow auto-merge"
  setting is off, or `main` has no required checks for the pull request to wait on), say so and
  leave the pull request open; do not merge it directly unless asked.
- Show examples for UI/UX decisions: whenever the owner is asked to choose between interface or
  interaction designs, show each option as a picture or mockup (rendered image, published
  mockup, or a preview in the question dialog) before asking. Never ask with descriptions alone.
