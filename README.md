# GNU a2ps 4.14 for SCO OpenServer 5

A working build of [GNU a2ps 4.14](https://www.gnu.org/software/a2ps/)
(September 2007) for **SCO OpenServer 5.0.7** — the "anything to
PostScript" pretty-printer. Turn plain text and source files into
PostScript with headers, borders and syntax highlighting, then send them
straight to a network PostScript printer.

```
$ a2ps --version
GNU a2ps 4.14

$ a2ps report.txt -o report.ps          # text -> PostScript
[report.txt (plain): 1 page on 1 sheet]

$ a2ps main.c -o - | \                    # C, syntax-highlighted, straight
    bash -c 'cat >/dev/tcp/192.168.1.50/9100'   # to a network printer
```

## Why 4.14 specifically?

Skunkware shipped a2ps **4.10.1** (~1998). The current release is 4.15.6
(2023). 4.14 is the last release of the "classic" line before the
project went dormant for 16 years, and it's the sweet spot for SCO:

- **It builds.** 4.15.x assumes a modern toolchain and pulls in
  **libpaper** plus a newer **gettext** — extra dependency chains to port
  first. 4.14 is contemporary with SCO's GCC 3.4 / gettext-0.14 world and
  builds with a single two-line fix (see [The one patch](#the-one-patch)).
- **It's a clean upgrade over 4.10.1** — ~9 years of bug fixes, better
  PostScript output (DSC compliance, Level 2/3), security fixes in the
  helper scripts (`fixps`, `psset`, …), and more bundled style sheets.

What 4.14 does **not** give you: proper UTF-8. a2ps stayed an 8-bit-era
tool until the 4.15 revival. If you need Unicode rendering you have to go
to 4.15 and port libpaper + modern gettext first. For ASCII / Latin-1
source and text — the normal SCO case — 4.14 is exactly right.

## Install

> **Fresh SCO box?** Install [curl with TLS](https://github.com/tachytelic/curl-7.88.1-for-SCO-OpenServer-5)
> first — that's the only file that needs to be transferred via `scp`.
> After that, every release on tachytelic/* (including this one) fetches
> over HTTPS from GitHub.

The release tarball is ~1.1 MB. **It must be installed at exactly
`/usr/local/a2ps-4.14`** — a2ps finds its PPDs, encodings and style
sheets through a path compiled into the binary, so (unlike curl) it is
not relocatable.

```sh
# On the SCO box (assumes curl-with-TLS is on PATH — see curl-sco):
curl -LO https://github.com/tachytelic/a2ps-4.14-for-SCO-OpenServer-5/releases/download/v1.0.0/a2ps-4.14-sco.tar.gz
gtar xzf a2ps-4.14-sco.tar.gz
# or with stock tools: gunzip -c a2ps-4.14-sco.tar.gz | /usr/bin/tar xf -
mv install /usr/local/a2ps-4.14
ln -s /usr/local/a2ps-4.14/bin/a2ps /usr/local/bin/a2ps
a2ps --version
```

The binary dynamically links against `/usr/lib/libc.so.1` and
`/usr/lib/libm.so.1` only — both stock SCO 5.0.7. **No external runtime
dependencies** (built `--disable-nls` specifically to avoid the
`libgnuintl` dependency that isn't present on a base SCO install).

## Printing to a network printer

a2ps produces PostScript; getting it onto paper is a separate step. The
two approaches that work well on SCO:

### Raw TCP to port 9100 (JetDirect / AppSocket)

Most network laser printers and print servers listen on **port 9100** and
accept a raw PostScript stream. SCO has no `nc`, but if you have
[bash 3.2.57](https://github.com/tachytelic/Bash-3.2.57-for-SCO-OpenServer-5)
its `/dev/tcp` pseudo-device does the job with no extra tools:

```sh
# Pretty-print a file and fire it straight at the printer:
a2ps main.c -o - | bash -c 'cat >/dev/tcp/192.168.1.50/9100'

# Or in two steps, if you want to keep the .ps:
a2ps main.c -o main.ps
bash -c 'exec 3<>/dev/tcp/192.168.1.50/9100; cat main.ps >&3; exec 3>&-'
```

This whole chain — a2ps 4.14 rendering → bash `/dev/tcp` → a PostScript
printer on port 9100 — was verified end-to-end on SCO 5.0.7: a real page
came out.

A tiny convenience wrapper:

```sh
# /usr/local/bin/a2ps-print  —  a2ps-print <printer-ip> <file>...
#!/bin/sh
ip=$1; shift
a2ps "$@" -o - | bash -c "cat >/dev/tcp/$ip/9100"
```

### Via the SCO spooler (`lp`)

If the printer is configured in SCO's print system, a2ps can hand off to
`lp` directly — set the default printing command and let a2ps invoke it:

```sh
a2ps -P printer_name main.c          # uses lp under the hood
a2ps main.c                          # to the default destination
```

The default spool command is set in `/usr/local/a2ps-4.14/etc/a2ps.cfg`
(`Printer: | lp ...`). Raw port-9100 is usually simpler on SCO because it
sidesteps spooler configuration entirely.

## What you get

- **Text → PostScript** with configurable headers/footers, borders,
  line numbering, multiple virtual pages per sheet (`-2`, `-4`, …).
- **Syntax highlighting** for a large set of languages via bundled style
  sheets in `share/a2ps/sheets/` (C, C++, shell, Perl, Python, make,
  HTML, SQL, and many more).
- **Encodings**: ASCII, Latin-1..Latin-15, and the usual 8-bit sets
  (no UTF-8 — see above).
- Helper tools: `fixps`, `psset`, `psmandup`, `pdiff`, `card`, and the
  `ogonkify` PostScript font-fixer.

### Handy invocations

```sh
a2ps -1 --medium=A4 notes.txt -o notes.ps      # 1-up, A4
a2ps -2 -o code.ps *.c                          # 2-up, all C files
a2ps --line-numbers=1 script.sh -o script.ps    # numbered lines
a2ps --columns=1 --no-header plain.txt -o p.ps  # minimal, 1 column
a2ps --list=languages                           # what it can highlight
a2ps --guess file.xyz                           # what a2ps thinks it is
```

## The one patch

a2ps 4.14 bundles a 2007-vintage gnulib whose `strtoimax`/`strtoumax`
modules expect `configure` to have run `AC_CHECK_DECLS([strtoll,
strtoull])` and recorded the result in `config.h`. This snapshot never
runs that test, so `HAVE_DECL_STRTOLL` / `HAVE_DECL_STRTOULL` are left
undefined and gnulib deliberately emits a bare string constant — an
intentional syntax error — to flag exactly that gap.

SCO 5.0.7's libc has neither function (not declared in `stdlib.h`, not
defined in libc), but gnulib already ships the replacement
implementations. Only the missing verdict has to be supplied, which
`build.sh` appends to `config.h` after configure:

```c
#define HAVE_DECL_STRTOULL 0
#define HAVE_DECL_STRTOLL 0
```

That's the entire SCO delta. a2ps's own code never calls `strtoumax` —
it's a vestigial gnulib dependency — so the fix is risk-free.

## Building from source

You probably don't need to — the release tarball is what `build.sh`
produces. This is a **native build** on SCO, same pattern as the
curl/nano/tar siblings.

### Requirements

- **GCC 3.4 or later** on PATH (or `CC=`/`GCC=` env var). Built with
  3.4.6; SCO's 2.95.3 may also work.
- `/usr/gnu/bin/{gmake,gtar}`
- **bash** as the configure shell (SCO's `/bin/sh` is `/bin/ksh`, far
  slower on autoconf scripts). Also needed at runtime for `/dev/tcp`
  printing.

### Build

```sh
cd a2ps-sco
./build.sh
```

Downloads `a2ps-4.14.tar.gz` from ftp.gnu.org, configures with
`--prefix=/usr/local/a2ps-4.14 --disable-nls`, applies the one-line
`config.h` fix above, builds, stages the install tree to `./install/`,
strips. Then `gtar czf a2ps-4.14-sco.tar.gz install`.

## Repository layout

```
build.sh                     Native-build script (run on SCO)
prebuilt/
  a2ps-4.14-sco.tar.gz       ~1.1 MB install tree (top-level install/)
LICENSE                      MIT (covers build script only)
README.md                    This file
```

The prebuilt tarball ships via the **[Releases](../../releases)** page.

## License

GNU a2ps is © Free Software Foundation, distributed under
[GPLv3+](https://www.gnu.org/licenses/gpl-3.0.html). The prebuilt binaries
are upstream a2ps 4.14 with no source changes — only the post-configure
`config.h` fix described above, which adds no code.

The build script in this repo is released under the MIT license — see
[LICENSE](LICENSE).

## See also

- [curl 7.88.1 for SCO](https://github.com/tachytelic/curl-7.88.1-for-SCO-OpenServer-5)
  — the natural first install on a fresh SCO box.
- [GNU bash 3.2.57 for SCO](https://github.com/tachytelic/Bash-3.2.57-for-SCO-OpenServer-5)
  — needed for the `/dev/tcp` network-printing trick above.
- [More SCO OpenServer 5 binaries](https://scoexpert.com/guides/sco-openserver-5-binaries/)
  — the hub.
