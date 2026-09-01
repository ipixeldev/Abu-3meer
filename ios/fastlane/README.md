fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Upload localized App Store metadata without changing the binary or submitting for review

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Upload localized App Store screenshots without changing metadata, the binary, or review state

### ios check_testflight

```sh
[bundle exec] fastlane ios check_testflight
```



### ios upload_testflight

```sh
[bundle exec] fastlane ios upload_testflight
```

Upload an existing IPA and distribute it to both Abu 3meer TestFlight groups

### ios select_app_store_build

```sh
[bundle exec] fastlane ios select_app_store_build
```

Select an already processed build for App Store version 1.1.0 without submitting for review

### ios submit_app_store_review

```sh
[bundle exec] fastlane ios submit_app_store_review
```

Submit App Store version 1.1.0 build 8 for review and release after approval

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
