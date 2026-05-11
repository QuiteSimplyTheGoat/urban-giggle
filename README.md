# urban-giggle

Public release bucket for ExsoLauncher runtime artifacts.

This repository intentionally contains only public build scripts and release
assets.

## macOS Java 25 Runtime

The launcher downloads the macOS code-mod runtime from the latest GitHub
Release:

```text
https://github.com/QuiteSimplyTheGoat/urban-giggle/releases/latest/download/java25-macos-exso.json
```

Release `java25-macos-exso.2` is expected to publish:

- `java25-macos-exso.json`
- `java_macos_exso-25.0.1-exso.2.jar`
- `java_macos_exso-25.0.1-exso.2.jar.sha256`

The runtime jar is a zip-compatible archive with `java_vm/` at its root.
