# Installing a release

Each release has three binaries: `sss-linux`, `sss-macos` and `sss-windows.exe`. Release assets don't keep the executable bit, so on Linux and macOS make the file executable after downloading it:

```bash
chmod +x sss-linux    # or sss-macos
```

**Linux requirements.** `sss-linux` needs glibc 2.34 or newer: Ubuntu 22.04, Debian 12, RHEL/Rocky/Alma 9, Fedora 35 and later. Debian 11 and Ubuntu 20.04 are too old. It is built on Ubuntu 22.04, and CI fails if a release binary needs a newer glibc (`.github/scripts/glibc_floor_check.sh`). It links libstdc++ and libgcc statically, so the shared libraries it needs at run time are exactly: OpenGL (`libGL.so.1`, `libGLU.so.1`), `libX11.so.6` and `libcurl.so.4`, plus glibc (`libc`, `libm`, the dynamic loader). Check with `readelf -d sss-linux | grep NEEDED`. On Debian/Ubuntu: `sudo apt install libgl1 libglu1-mesa libx11-6 libcurl4`. On RHEL/Rocky 9: `sudo dnf install mesa-libGL mesa-libGLU libX11 libcurl` (`mesa-libGLU` comes from the CRB repo: `--enablerepo=crb`).

**macOS requirements.** macOS 12 (Monterey) or newer on Apple Silicon. CI builds with `MACOSX_DEPLOYMENT_TARGET=12.0` and fails if the binary's minimum OS version (`minos`) is anything else (`.github/scripts/macos_minos_check.sh`). There is no Intel build.

**Windows requirements.** Windows 10 or newer (64-bit).

macOS also quarantines files downloaded from the internet and won't open an unsigned binary. Clear the flag with `xattr -d com.apple.quarantine sss-macos`, or right-click the file in Finder, choose **Open**, and confirm.
