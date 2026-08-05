# Sparkle + GitHub Releases

Orbit uses Sparkle for app updates and GitHub Releases as the update host.

## One-time setup

1. Resolve Swift packages in Xcode or with:

   ```bash
   xcodebuild -resolvePackageDependencies -project Orbit.xcodeproj -scheme Orbit
   ```

2. Generate the Sparkle EdDSA key:

   ```bash
   /path/to/Sparkle/bin/generate_keys
   ```

3. Use the printed public key when building releases:

   ```bash
   ORBIT_SPARKLE_PUBLIC_ED_KEY="<public key>" Scripts/release-github-sparkle.sh 1.0.1
   ```

   The private key stays in your login Keychain. Keep it backed up.

## Release

The script builds `Orbit.app`, creates `Orbit-<version>.zip`, generates
`appcast.xml`, and uploads both files to GitHub Releases.

The appcast URL embedded in the app is:

```text
https://github.com/kohichiwa/Orbit-MacOS/releases/latest/download/appcast.xml
```
