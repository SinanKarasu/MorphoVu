# ManifoldCore

`ManifoldCore` wraps the upstream [Manifold](https://github.com/elalish/manifold) C++
library in a Swift package that exposes a Swift-friendly `ManifoldKit` API.

## Bootstrap

Before building the package, bootstrap the vendored native dependency:

```bash
make bootstrap
```

That script will:

- clone or update the upstream `elalish/manifold` repository into `.build/`
- build static Manifold archives for macOS, visionOS, and the visionOS simulator
- stage public headers into `vendor/manifold-include`
- stage a static `ManifoldBinary.xcframework` into `vendor/`

## Build

```bash
swift build
```

Or open the package in Xcode after bootstrapping.

## Layout

- `Sources/ManifoldBridge`: thin C++ wrapper imported by Swift C++ interop
- `Sources/ManifoldKit`: public Swift API
- `Scripts/bootstrap-manifold.sh`: native dependency bootstrap
- `vendor/manifold-include`: staged upstream headers
- `vendor/ManifoldBinary.xcframework`: staged multi-platform static library

## Notes

- The package expects `cmake` and a working C++ toolchain to be installed.
- The bootstrap script is safe to re-run; it updates the staged artifacts in place.
