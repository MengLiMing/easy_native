## 0.0.2

* Refactor: Removed `ResultDart` dependency. Routing APIs now return `T?` directly and throw `EasyNativeRouteFailure` on error.
* Fix: Fixed memory leak in Native Flow RequestIDs collection.
* Fix: Added fallback logic for iOS `pushAndRemoveUntil` when no active native flow exists.
* Feature: Support Swift Package Manager (SPM).

## 0.0.1

* Initial release.
