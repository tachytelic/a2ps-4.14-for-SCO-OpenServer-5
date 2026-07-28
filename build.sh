#!/bin/sh
# Build GNU a2ps 4.14 natively on SCO OpenServer 5.0.7.
#
# Run this script ON the SCO machine, in a writable directory.
#
# Required:
#   GCC 3.4 or later (the SCO native 2.95.3 may also work). Set CC and
#       put it on PATH, or override via the GCC env var below.
#   /usr/gnu/bin/{gmake,gtar}
#   bash (used as configure shell — SCO's /bin/sh is /bin/ksh, which is
#       dramatically slower on autoconf-generated configure scripts)
#   curl or wget, OR drop a2ps-4.14.tar.gz next to this script
#
# Output: ./install/  — the a2ps tree, ~2.2 MB. Package it with
#         `gtar czf a2ps-4.14-sco.tar.gz install`.
#
# IMPORTANT — the install PREFIX is baked into the binary. a2ps locates
# its PPDs, encoding maps and style sheets via that compiled-in path, so
# unlike a single-file binary (curl/lua) this package is NOT relocatable:
# it must end up at exactly /usr/local/a2ps-4.14 on the target box. The
# tarball is built from an install staged for that prefix.
#
# Dynamic deps of the result: /usr/lib/libc.so.1 and /usr/lib/libm.so.1
# only — both stock SCO 5.0.7. (Built with --disable-nls precisely so it
# does NOT pull in libgnuintl from the gwxlibs add-on, which is not
# present on a base SCO install.)

set -e

SCRIPT_DIR=`cd \`dirname "$0"\` && pwd`
VERSION=4.14
TARBALL=a2ps-${VERSION}.tar.gz
SRCDIR=a2ps-${VERSION}
PREFIX=/usr/local/a2ps-${VERSION}

if [ -n "$GCC" ]; then
    CC="$GCC"
elif [ -z "$CC" ]; then
    if which gcc-3.4.6 >/dev/null 2>&1; then
        CC=gcc-3.4.6
    else
        CC=gcc
    fi
fi
export CC

# /usr/local/bin first: that's where gcc-3.4.6, bash and curl live.
PATH=/usr/local/bin:/usr/gnu/bin:/usr/ccs/bin:/usr/bin:/bin
export PATH

# a2ps 4.14's configure is old but occasionally trips SCO's stock /bin/rm
# in the same overly-strict autoconf check curl hit. Harmless to set.
ACCEPT_INFERIOR_RM_PROGRAM=yes
export ACCEPT_INFERIOR_RM_PROGRAM

if [ ! -f "$TARBALL" ]; then
    echo "Fetching $TARBALL..."
    if which curl >/dev/null 2>&1; then
        curl -kLO "https://ftp.gnu.org/gnu/a2ps/${TARBALL}"
    elif which wget >/dev/null 2>&1; then
        wget --no-check-certificate "https://ftp.gnu.org/gnu/a2ps/${TARBALL}"
    else
        echo "ERROR: no curl or wget. Drop $TARBALL next to this script." >&2
        exit 1
    fi
fi

if [ ! -d "$SRCDIR" ]; then
    echo "Unpacking $TARBALL..."
    gzip -dc "$TARBALL" | tar xf -
fi

cd "$SRCDIR"

# Prefer bash as the configure shell — much faster than SCO's ksh on the
# large autoconf script. Falls back to the default shell if bash is absent.
SHELL_BIN=`which bash 2>/dev/null || true`

echo "Configuring..."
# --disable-nls — drop the gettext/libintl dependency. a2ps then needs
#                 only base-system libc + libm, so the binary runs on a
#                 bare SCO box with no gwxlibs add-on. NLS only affected
#                 the *language of a2ps's own messages*, never what it can
#                 render or print, so this is pure portability upside.
if [ -n "$SHELL_BIN" ]; then
    CONFIG_SHELL="$SHELL_BIN" "$SHELL_BIN" configure \
        --prefix="$PREFIX" --disable-nls CC="$CC" CFLAGS="-O2"
else
    ./configure --prefix="$PREFIX" --disable-nls CC="$CC" CFLAGS="-O2"
fi

# --- SCO source fix (the one and only patch) --------------------------
# a2ps 4.14 bundles a 2007-vintage gnulib. Its strtoimax/strtoumax modules
# expect configure to have run AC_CHECK_DECLS([strtoll, strtoull]) and
# defined HAVE_DECL_STRTOLL / HAVE_DECL_STRTOULL (to 0 or 1). This gnulib
# snapshot never runs that test, so config.h leaves both undefined, and
# gnulib deliberately emits a bare "this configure-time declaration test
# was not run" string constant — a syntax error — to catch exactly that.
#
# SCO 5.0.7 libc has neither strtoll nor strtoull (not declared in
# stdlib.h, not defined in libc). gnulib already ships the replacement
# implementations (lib/strtoull.c), so all that's actually missing is the
# verdict. We supply it. (a2ps's own code never calls strtoumax — it's a
# vestigial gnulib dependency — so this is risk-free.)
echo "Applying SCO strtoull/strtoll config.h fix..."
cat >> config.h <<'EOF'

/* SCO fix: libc lacks strtoll/strtoull decls; gnulib supplies the impls. */
#ifndef HAVE_DECL_STRTOULL
#define HAVE_DECL_STRTOULL 0
#endif
#ifndef HAVE_DECL_STRTOLL
#define HAVE_DECL_STRTOLL 0
#endif
EOF
# ----------------------------------------------------------------------

echo "Compiling..."
gmake

echo "Staging install for prefix $PREFIX ..."
# Install into a DESTDIR staging root, then lift the prefix tree out as
# ./install so it can be tarred and dropped straight onto /usr/local of a
# target box (mv install /usr/local/a2ps-4.14).
rm -rf "$SCRIPT_DIR/pkgroot" "$SCRIPT_DIR/install"
gmake -s install DESTDIR="$SCRIPT_DIR/pkgroot"
mv "$SCRIPT_DIR/pkgroot$PREFIX" "$SCRIPT_DIR/install"
rm -rf "$SCRIPT_DIR/pkgroot"

echo "Stripping..."
strip "$SCRIPT_DIR/install/bin/a2ps" 2>/dev/null || true

ls -l "$SCRIPT_DIR/install/bin/a2ps"
echo
echo "Built: $SCRIPT_DIR/install/  (compiled prefix: $PREFIX)"
echo
echo "To package:  gtar czf a2ps-${VERSION}-sco.tar.gz install"
echo
echo "To install on this or another SCO box (MUST be this exact path):"
echo "  mv install $PREFIX"
echo "  ln -s $PREFIX/bin/a2ps /usr/local/bin/a2ps"
echo
echo "Test:  a2ps --version"
echo "       echo hello | a2ps -o /tmp/t.ps && file /tmp/t.ps"
