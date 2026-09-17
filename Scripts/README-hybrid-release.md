# Hybrid release flow

Local Mac builds the DMG; CI only creates the GitHub Release with generated notes when a version tag is pushed. No notarize and no CI binary build.

1. **Build the DMG locally** on the Mac mini (existing packaging scripts: `Scripts/package_dmg.sh`).
2. **Tag and push** a version tag (`v*`), e.g. `git tag v0.3.0 && git push origin v0.3.0`.
3. **CI creates the release** (`.github/workflows/release-on-tag.yml`) with generated notes — no binaries.
4. **Attach the asset(s)** with `Scripts/attach-release-asset.sh`:

   ```bash
   Scripts/attach-release-asset.sh v0.3.0 ./dist/NODAYSIDLE-Voice-0.3.0.dmg
   # or multiple:
   Scripts/attach-release-asset.sh v0.3.0 ./dist/NODAYSIDLE-Voice-0.3.0.dmg ./path/to/other.zip
   ```

Existing Latest release is **v0.2.0**. This automation does not republish or replace it; a new `v*` tag is required for a new release.
