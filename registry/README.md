# registry/

Community addons and themes for the official repository.

Community addons stay in their authors' own repos. To list one, open a PR adding a JSON file here that points at its release zip. The release script downloads it, checks the manifest and checksum, and includes it in the published `index.json` marked as community.

Format to be defined with the repo index (see [PLAN.md §9](../PLAN.md#repo-index-format-v2-draft)).
