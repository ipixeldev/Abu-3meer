# Shorebird hotfix updates

Shorebird is configured per Shorebird account, not by a Flutter package. Run this once on a machine with the Shorebird CLI and the Apple/Google signing credentials:

```bash
cd "/Users/ipixeldev/Desktop/Abu3meer Demo"
shorebird login
shorebird init                 # choose the existing abu_3meer Flutter project
shorebird release ios          # publish a store build with Shorebird
shorebird patch ios            # ship Dart/UI fixes to that released build
```

The generated `shorebird.yaml` contains the account-specific app ID and must be committed. A patch cannot change native code, entitlements, plugins, or store metadata; those changes still require a new App Store/Play release. Test every patch before publishing:

```bash
shorebird preview
shorebird patch ios --dry-run
```

Never put App Store Connect keys, RevenueCat secret keys, or signing certificates in this repository. Shorebird release/patch commands should run only from a trusted machine or CI secret store.
