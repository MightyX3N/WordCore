# tools/

Scripts for building and releasing.

## Planned

- **Build** the `wordcore` program for every target (`runtime/`)
- **Package** releases: program + core per platform
- **Release addons/themes**: zip each one, compute SHA-256, sign (if we decide to), write `index.json` to the `repo` branch
- **Registry check**: fetch community addons listed in `registry/`, verify their zips and manifests, include them in the index
- **Dev helpers**: run a local site, reset a test site, run a local test repo
