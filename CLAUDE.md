# FishingStats

World of Warcraft addon (pure Lua, `Interface/AddOns` addon layout). See [README.md](README.md) for what it does.

## Release process

This addon is configured for automatic publishing to CurseForge. Publishing a new version is done by pushing a git tag:

```
git tag <version>
git push --tag
```

To see existing tags: `git tag -l`

### Version bump policy

- When told to "publish" or "release" without further qualification, default to a **patch/minor** version bump (e.g. `1.1.3` → `1.1.4` or `1.2`).
- Only bump the **major** version when explicitly told to.
