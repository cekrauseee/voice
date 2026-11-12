# Releasing

A release is a version tag. Pushing it publishes a GitHub Release with the app in a disk image.

```sh
git switch main && git pull
git tag -a v0.1.0 -m v0.1.0
git push origin v0.1.0
```

The [release workflow](../.github/workflows/release.yml) then:

1. Runs `pnpm verify` on the tagged commit.
2. Builds the app with the tag as its version, in a disk image, `Voice.dmg`.
3. Publishes a GitHub Release named after the tag, with `Voice.dmg` attached and notes generated from the merged pull requests.

A release created on GitHub, with a new tag, works too: the workflow runs for the tag and attaches `Voice.dmg` to that release.

Versions follow [semantic versioning](https://semver.org). Before 1.0, a minor version can change the protocol: release the app and deploy the server from the same tag.

## Installing

From a release, open `Voice.dmg` and drag Voice to Applications.

On a Mac with the repository, `pnpm install-app` installs the app from the checkout, or updates it, with the same build and disk image as a release: see [the desktop README](../apps/desktop/README.md#builds). To install a release this way, check out its tag first:

```sh
git switch --detach v0.1.0
pnpm install-app
```

## Limits

The released app is signed ad hoc and is not notarized, because the workflow has no Apple Developer ID. On another Mac, macOS blocks it on first open: allow it in System Settings, under Privacy & Security. Its permissions are also asked for again after every update. `pnpm install-app` has neither limit: the app is built on the Mac it runs on, and signed with the Apple Development identity in its keychain.

The server is not packaged. Run it from the tagged source with `pnpm start`.
