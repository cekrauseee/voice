# Releasing

A release is a version tag. Pushing it publishes a GitHub Release with the app.

```sh
git switch main && git pull
git tag v0.1.0
git push origin v0.1.0
```

The [release workflow](../.github/workflows/release.yml) then:

1. Runs `pnpm verify` on the tagged commit.
2. Builds `Voice.app` with the tag as its version.
3. Publishes a GitHub Release named after the tag, with `Voice.zip` attached and notes generated from the merged pull requests.

Versions follow [semantic versioning](https://semver.org). Before 1.0, a minor version can change the protocol: release the app and deploy the server from the same tag.

## Limits

The released app is signed ad hoc and is not notarized, because the workflow has no Apple Developer ID. On another Mac, macOS blocks it on first open: allow it in System Settings, under Privacy & Security. Its permissions are also asked for again after every update.

The server is not packaged. Run it from the tagged source with `pnpm start`.
