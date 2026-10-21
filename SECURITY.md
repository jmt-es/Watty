# Security policy

## Supported versions

Only the latest release receives security fixes.

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub security advisories for `jmt-es/Watty`: open the [Security tab](https://github.com/jmt-es/Watty/security) of this repository and choose **Report a vulnerability**, or go straight to the [advisory form](https://github.com/jmt-es/Watty/security/advisories/new). Do not open a public issue for a vulnerability. If you cannot use the form, open an issue that only says you have a security report, with no details, and the maintainer will arrange a private channel.

Include what you can of:

- the Watty version (`watty --version`, or About Watty in the panel menu), your macOS version and your Mac model,
- the steps to reproduce the problem,
- what an attacker could do with it.

Watty is maintained by one person. You can expect an acknowledgment within a week, and a fix or an explanation as soon as possible after that. Please give the fix some time before you publish the details. Credit is given in the release notes unless you prefer otherwise.

## What Watty does

- The app and the `watty` command make no network requests and send no data anywhere. The source contains no networking code.
- They read power and process information that macOS exposes to normal users, and they run a few system tools to read more (`pmset`, `system_profiler` and `ps`, and `ioreg` as a fallback) and parse their output with fixed patterns.
- They write only Watty's own settings and battery history under your home folder.
- Changing the energy mode is the only privileged action. Watty asks `osascript` to run `pmset` with administrator privileges, which shows the standard macOS authorization prompt, and Watty never sees the administrator password.
- Watty has no third-party dependencies.

Ways other software can talk to a running Watty are deliberately narrow:

- A `watty://` URL, and the local notification that `watty show` posts, only bring the panel to the front. They carry no commands and no paths.
- The launch arguments that write a screenshot (`--capture-panel` and `--capture-settings`) only take effect when Watty is launched with them. A URL or a message to a running Watty cannot set them.
- The battery history file is checked and sanitized when it is loaded. A file that cannot be read is set aside and a new one starts.

## What counts as a vulnerability

- Anything that lets Watty, or input it reads, run commands with more privilege than the single `pmset` change it asks for.
- Anything that makes the app contact the network or leak data.
- A way for a URL, another app or a crafted file to make Watty write or delete files outside its own data.
- A flaw in the install, uninstall or release scripts, the GitHub workflows or the Homebrew formula that could harm the machine they run on or tamper with a release.

## What does not count

- Prebuilt releases are signed ad hoc and are not notarized, because there is no Apple Developer ID behind the project. This is known. Verify a download against the SHA-256 file attached to the release, or install with Homebrew, which builds the app on your Mac.
- Problems that need a Mac that is already compromised, or an administrator password you gave away.
- Bugs in macOS, Homebrew or Apple's frameworks. Report those to their owners.
- Wrong or missing readings, and the use of the undocumented IOKit HID interface for the chip temperature. Open a normal issue for those.
