# Extension compatibility

2026-10-18. "Verified" means run on a phone with a real project. **Nothing below is verified yet.**

Extensions run on the phone side. They can start programs the phone can run; they cannot start Ubuntu's programs. The
terminal and shell tasks run in Ubuntu through the routing described in UBUNTU_ROUTING.md.

| Extension | Needs | State |
|-----------|-------|-------|
| Code Runner | A shell with the routed commands; the app sets it to run in the terminal | Configured; not verified |
| NPM Scripts / npm tasks | `npm` | Shell task; not verified |
| Language Support for Java (Red Hat), Debugger for Java | A JDK that runs on the phone (`JAVA_HOME`) | Works only with a phone-side JDK, not Ubuntu's; not verified |
| C/C++ (Microsoft) | Marketplace terms allow Microsoft products only; desktop-C-library binaries | **Not supported** |
| clangd (Open VSX) | A clangd the phone can start | **Not provided.** Ubuntu's clangd cannot be started by the extension directly |
| Python | The phone's Python | Existing behaviour; unchanged |

Tools needed in Ubuntu for terminal workflows are installed with `apt` (`which TOOL` shows whether one is present). Nothing is
preinstalled to avoid an install step.
