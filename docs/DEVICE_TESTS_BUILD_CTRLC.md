# Device tests: build tasks, extensions, Ctrl+C

None has been run on a phone yet. Record the result next to each line.

| # | Test | Expected |
|---|------|----------|
| B1 | Project with `.vscode/tasks.json`: `{"label":"build","type":"shell","command":"gcc -g main.c -o main"}`; Terminal > Run Build Task | Task terminal shows no error; `main` appears in the project folder |
| B2 | A task with a deliberate error in `main.c` | The error text appears; the task is marked failed; the editor and other terminals keep working |
| B3 | A task with `"options": {"cwd": "${workspaceFolder}/sub"}` and `"env"` | Runs in `sub` with the variable set |
| B4 | A task that `dependsOn` another | Runs in order |
| B5 | Install Code Runner; run a `.c`, a `.py` and a `.cpp` sample | Output appears in the terminal; the C program runs (Ubuntu) |
| B6 | Open `package.json`; run a script from the NPM Scripts view or Run Task > npm | The script runs; output in the task terminal |
| B7 | A `"type":"process"` task with `"command":"gcc"` | Expected to fail (known limit); confirm the message is clear |
| C1 | `ubuntu python3 -c "import time; time.sleep(99)"`, tap Ctrl on the extra key row, then c | Stops with a KeyboardInterrupt message; prompt returns |
| C2 | `npm start` (or `python3 -m http.server`), Ctrl+C | Server stops; `curl localhost:PORT` fails afterwards |
| C3 | `ubuntu` (Ubuntu shell), Ctrl+C at the prompt | Prompt returns; the session is not closed |
| C4 | A Python script that catches SIGINT and prints a message; run through `python3 x.py`, Ctrl+C | The message prints (the program handled it itself) |
| C5 | Select text in the editor, Ctrl then c | Text is copied |
| C6 | Two terminals: one runs a server, press Ctrl+C in the other | The server keeps running |
| C7 | Set `VSCODROID_UB_NO_JOB=1` and repeat C1 | Still stops (the older behaviour); useful if C1 fails |
