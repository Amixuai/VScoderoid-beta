# Extension compatibility

2026-10-20. "Verified" means run on a phone with a real project. **Nothing below is verified yet.**

Extensions run on the phone side. They can start programs the phone can run. A program an extension (or a `"type": "process"` task) starts by name reaches Ubuntu only for `gcc`, `g++`, `cc`, `c++`, `cpp`, `cmake`, `cargo` and `rustc`, through launcher rows written in Update-11 (not run on a phone yet); every other Ubuntu program, `clangd` included, is out of an extension's reach. The
terminal and shell tasks run in Ubuntu through the routing described in UBUNTU_ROUTING.md.

| Extension | Needs | State |
|-----------|-------|-------|
| Code Runner | A shell with the routed commands; the app sets it to run in the terminal | Configured; not verified |
| NPM Scripts / npm tasks | `npm` | Shell task; not verified |
| Language Support for Java (Red Hat), Debugger for Java | A JDK that runs on the phone (`JAVA_HOME`) | Works only with a phone-side JDK, not Ubuntu's; not verified |
| C/C++ (Microsoft) | Marketplace terms allow Microsoft products only; desktop-C-library binaries | **Not supported** |
| clangd (Open VSX) | A clangd the phone can start | **Not provided.** Ubuntu's clangd cannot be started by the extension directly |
| Prettier, ESLint, Tailwind CSS IntelliSense (bundled in the APK) | `node` for ESLint and the Tailwind server; Prettier runs in the extension host | Bundled by `scripts/download-extensions.sh`; activation and results not verified on a phone |
| Code Runner, NPM Scripts, Java, C/C++, clangd | Not bundled; installed from Open VSX by the user | See the rows above |
| Python | The phone's Python | Existing behaviour; unchanged. Note: in the terminal `python`/`pip` go to Ubuntu once it is installed, but a process task or an extension uses the phone's own, so packages installed through the terminal are not seen by it |
| Extensions or tasks that start `gcc`, `g++`, `cmake`, `cargo`, `rustc` by name | Ubuntu installed (it installs itself on first use) | Launcher rows written; Kotlin not compiled, not run on a phone |

Tools needed in Ubuntu for terminal workflows are installed with `apt` (`which TOOL` shows whether one is present). Nothing is
preinstalled to avoid an install step.
