---
name: diagnose-crash
description: >
  Diagnose why a program crashed on this machine, from a systemd-coredump core dump.
  Use when a process has segfaulted, aborted, or otherwise dumped core, when asked
  why an application crashed or disappeared, or when a "Process crashed:" desktop
  notification is acted on. Triggers: crash, segfault, SIGSEGV, SIGABRT, core dump,
  coredumpctl, "why did X crash", "X keeps crashing", backtrace symbolization.
  Covers reporting a confirmed Omarchy bug upstream — see reporting.md.
---

# Diagnosing a Crash

Work from evidence. The goal is an honest account of what happened, not a
plausible-sounding story.

## Establish the facts

`coredumpctl info <pid>` is the starting point. Beyond the backtrace, note the
**command line** the process was started with — it usually reveals what the
program was working on when it died, which is often the whole answer.

`coredumpctl list` shows whether this crash is a one-off or a pattern. Repeated
crashes of the same program, or several programs dying together, point somewhere
different than a single failure does.

## Rule out the boring causes first

Check resource exhaustion before blaming the program: `free -h`, and the journal
for OOM kills. A process killed by the OOM killer is not a bug in that process.

Resource exhaustion is not only host RAM. For anything touching the GPU, check
`nvidia-smi` for VRAM and look for driver-side allocation failures in the journal
(`Failed to allocate ... video memory`, `trying to fall back to sysmem`). A GPU
under VRAM pressure from other resident processes is a legitimate trigger, and the
kernel usually says so at the moment it happens.

## Correlate against the timeline

The crash timestamp is the most underused piece of evidence. Compare it against:

- **Filesystem mtimes.** A directory or file whose mtime lands on the same second
  as the crash strongly suggests what triggered it.
- **The journal** around that moment, for related warnings from the same or
  neighbouring processes.
- **Recent package updates.** A crash that starts right after an update points at
  the update.

Use `journalctl -o short-precise` when several events share a second. Sub-second
ordering is what separates a cause from a consequence — kernel messages landing
tens of milliseconds *before* the signal are a lead; the same messages after it
are just the aftermath.

## Read the whole core, not just frame 0

Thread stacks other than the crashing one show what work was **in flight** —
thumbnailers, image loaders, IPC readers, GPU queues. That context often explains
the trigger even when the crashing frame itself cannot be symbolized.

Note any third-party code in the address space: file-manager or browser
extensions, plugins, out-of-tree drivers. In-process third-party code is a common
crash source and worth flagging — but do not pin blame on it without evidence
that it is actually implicated.

`info sharedlibrary` lists what was actually mapped, which beats guessing from the
flags: it shows whether a plugin, codec or driver really was loaded. Where a child
process crashed, remember the command line of the **parent** — a browser's GPU or
renderer process carries only a subset of the parent's flags, so its argv is not
the launch configuration.

Read the fault itself, not just the frames. The fault address and the faulting
instruction separate a null dereference from wild corruption, and say which
library's data the code was reaching for:

```bash
gdb -q <exe> "$core" -batch -iex 'set debuginfod enabled off' \
  -ex 'p $_siginfo._sifields._sigfault.si_addr' \
  -ex 'info registers rip rax rdi rsi' \
  -ex 'x/3i $pc'
```

A small fault address (hundreds of bytes to a few KB) with a zeroed base register
is a NULL dereference of a struct field — the library expected an object that was
never created. A large, random address points at corruption instead. The two lead
to different reports.

## Symbolize when you can

This is Arch, which runs a public debuginfod server:

```bash
core=$(mktemp -t crash-XXXXXX.core)
trap 'rm -f "$core"' EXIT
coredumpctl dump <pid> --output="$core"
DEBUGINFOD_URLS="https://debuginfod.archlinux.org" \
  gdb -q <executable> "$core" \
  -batch -iex 'set debuginfod enabled on' -ex 'bt'
```

A core is a verbatim copy of the process's memory and can hold passwords, tokens,
and private documents. Write it to a fresh `mktemp` path rather than a predictable
shared one, and delete it when you are done — never leave it lying in `/tmp`.

A long gdb run can be killed by a timeout before the `rm` executes, leaving a
multi-hundred-megabyte memory image behind. Check for stray `*.core` files before
you finish rather than assuming the cleanup ran.

`-iex` is required, not `-ex`: gdb asks whether to enable debuginfod *before* it
runs any `-ex` command, so with `-ex` the answer silently defaults to no and the
setting never takes effect. `-iex` runs early enough to win.

Watch what debuginfod downloads. gdb fetches debuginfo per object file as it
unwinds, so symbolizing a browser pulls that browser's own multi-gigabyte debug
package — a run that can hang for many minutes and still leave the interesting
frames unresolved. When the interesting frames sit in a small library (libGLX,
libc, libglvnd) rather than the main binary, skip debuginfod and read the offsets
against that library's dynamic symbols instead:

```bash
nm -D --defined-only /usr/lib/libGLX.so.0 | sort | awk 'strtonum("0x"$1) <= 0x18aa8' | tail -3
```

That names the exported function an offset falls inside. An offset can also land
in a static helper that exports nothing, in which case you can only bracket it
between the two nearest exports — say so rather than naming a function you did
not verify.

Many packages publish no debug symbols. When frames stay unresolved, say so —
never invent function names to fill the gap. An unsymbolized stack still has
shape: which library each frame belongs to, and whether the crash came from a
signal handler, a main loop, or a worker thread.

## Report

1. What crashed, and what it was doing at the time.
2. The most likely mechanism — separating clearly what the evidence **proves**
   from what you are **inferring**.
3. Whether any user data was lost, and where it can be recovered from. Check the
   trash before concluding anything is gone.
4. Whether it is likely to recur, and what would avoid or fix it.

Be straight about the limits of the evidence. If the cause is genuinely
ambiguous, say so rather than assembling confidence out of guesswork.

**Leave the system as you found it.** Diagnosis reads; it does not fix, tidy, or
reconfigure. The one thing to clean up is your own: delete the core you extracted
above, which is a copy of the crashed process's memory. The single change a
diagnosis may make is the mute below, and only when the user asks for it.

## Offer to stop the notifications for this program

A crash you have explained often keeps happening anyway. Finish by offering to
silence notifications for **that one program**, and never run it unprompted. Say
how to lift it in the same breath, so it is not a one-way door.

```bash
omarchy-crash-mute '<program>'        # silence it
omarchy-crash-mute '<program>' off    # let it speak again
omarchy-crash-mute                    # list what is muted
```

Pass the `binary:` path from the crash facts, or the `process:` name where no
binary was recorded; the command reduces either to the name the watcher keys on.
A diagnosis run by hand from `omarchy agent crash <pid>` has neither, so take
them from `coredumpctl info`. Prefer the binary: a process name is truncated to
15 characters and a basename is not, so muting the truncated form matches
nothing, forever, while looking like it worked.

Quote it. The name is whatever the crashed program's author called a file, and a
single quote inside one closes yours and runs the rest as your shell.

The key is a bare name, so anything run through an interpreter is keyed as the
interpreter: muting `python3.13` silences every Python program on the machine.
Say so rather than quietly doing it.

None of this fixes anything, and a mute offered in place of a fix that was within
reach is the wrong answer. For every program rather than one, the switch is
_Trigger > Toggle > Crash Capture_.

## If it is an Omarchy bug

Most application crashes are upstream bugs in those applications, not Omarchy's
doing. In the minority of cases where the cause really does sit within Omarchy's
sphere of control, read [`reporting.md`](reporting.md) before offering to file
anything.
