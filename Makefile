# -*- makefile-gmake -*-

.PHONY: dist mips-dist cleaner distclean dist-clean test test-all test-dist checkdefs debian snowballs init-dev
.DEFAULT_GOAL := all

CHIBI_VERSION ?= $(shell cat VERSION)
SOVERSION ?= $(CHIBI_VERSION)
SOVERSION_MAJOR ?= $(shell echo "$(SOVERSION)" | sed "s/\..*//")

CHIBI_FFI ?= $(CHIBI) -q tools/chibi-ffi
CHIBI_FFI_DEPENDENCIES ?= $(CHIBI_DEPENDENCIES) tools/chibi-ffi

CHIBI_DOC ?= $(CHIBI) tools/chibi-doc
CHIBI_DOC_DEPENDENCIES ?= $(CHIBI_DEPENDENCIES) tools/chibi-doc $(COMPILED_LIBS)

GENSTATIC ?= ./tools/chibi-genstatic

CHIBI ?= LD_LIBRARY_PATH=".:$(LD_LIBRARY_PATH)" DYLD_LIBRARY_PATH=".:$(DYLD_LIBRARY_PATH)" CHIBI_IGNORE_SYSTEM_PATH=1 CHIBI_MODULE_PATH=lib ./chibi-scheme$(EXE)
CHIBI_DEPENDENCIES = ./chibi-scheme$(EXE)

SNOW_CHIBI ?= tools/snow-chibi

########################################################################

CHIBI_COMPILED_LIBS = lib/chibi/filesystem$(SO) lib/chibi/weak$(SO) \
	lib/chibi/heap-stats$(SO) lib/chibi/disasm$(SO) lib/chibi/ast$(SO) \
	lib/chibi/json$(SO) lib/chibi/emscripten$(SO)
CHIBI_POSIX_COMPILED_LIBS = lib/chibi/process$(SO) lib/chibi/time$(SO) \
	lib/chibi/system$(SO) lib/chibi/stty$(SO) lib/chibi/pty$(SO) \
	lib/chibi/net$(SO) lib/srfi/18/threads$(SO)
CHIBI_WIN32_COMPILED_LIBS = lib/chibi/win32/process-win32$(SO)
CHIBI_CRYPTO_COMPILED_LIBS = lib/chibi/crypto/crypto$(SO)
CHIBI_IO_COMPILED_LIBS = lib/chibi/io/io$(SO)
CHIBI_OPT_COMPILED_LIBS = lib/chibi/optimize/rest$(SO) \
	lib/chibi/optimize/profile$(SO)
EXTRA_COMPILED_LIBS ?=

COMPILED_LIBS = $(CHIBI_COMPILED_LIBS) $(CHIBI_IO_COMPILED_LIBS) \
	$(CHIBI_OPT_COMPILED_LIBS) $(CHIBI_CRYPTO_COMPILED_LIBS) \
	$(EXTRA_COMPILED_LIBS) \
	lib/srfi/27/rand$(SO) lib/srfi/151/bit$(SO) \
	lib/srfi/39/param$(SO) lib/srfi/69/hash$(SO) lib/srfi/95/qsort$(SO) \
	lib/srfi/98/env$(SO) lib/srfi/144/math$(SO) lib/srfi/160/uvprims$(SO) \
	lib/scheme/bytevector$(SO) lib/scheme/time$(SO)

BASE_INCLUDES = include/chibi/sexp.h include/chibi/features.h include/chibi/install.h include/chibi/bignum.h
INCLUDES = $(BASE_INCLUDES) include/chibi/eval.h include/chibi/gc_heap.h

MODULE_DOCS := app assert ast base64 binary-record bytevector config \
	crypto/md5 crypto/rsa crypto/sha2 diff disasm doc edit-distance \
	equiv filesystem generic heap-stats io \
	iset/base iset/constructors iset/iterators json loop \
	match math/prime memoize mime modules net net/http-server net/servlet \
	optional parse pathname process repl scribble string stty sxml system \
	temp-file test time trace type-inference uri weak monad/environment \
	crypto/sha2 shell

IMAGE_FILES = lib/chibi.img lib/red.img lib/snow.img

HTML_LIBS = $(MODULE_DOCS:%=doc/lib/chibi/%.html) doc/lib/srfi/166/base.html

META_FILES = lib/.chibi.meta lib/.srfi.meta lib/.scheme.meta

########################################################################
# This includes the rules to build optional libraries.
# It also pulls in Makefile.detect for platform detection.

include Makefile.libs

########################################################################

all: chibi-scheme$(EXE) all-libs chibi-scheme.pc $(META_FILES)

# Please run this if you want to contribute.
init-dev:
	git config core.hooksPath .githooks

js: js/chibi.js

js/chibi.js: chibi-scheme-emscripten chibi-scheme-static.bc js/pre.js js/post.js js/exported_functions.json
	emcc -O0 chibi-scheme-static.bc -o $@ -s ALLOW_MEMORY_GROWTH=1 -s MODULARIZE=1 -s EXPORT_NAME=\"Chibi\" -s EXPORTED_FUNCTIONS=@js/exported_functions.json `find  lib -type f \( -name "*.scm" -or -name "*.sld" \) -printf " --preload-file %p"` -s 'EXTRA_EXPORTED_RUNTIME_METHODS=["ccall", "cwrap"]' --pre-js js/pre.js --post-js js/post.js

chibi-scheme-static.bc:
	emmake $(MAKE) PLATFORM=emscripten CHIBI_DEPENDENCIES= CHIBI=./chibi-scheme-emscripten PREFIX= CFLAGS=-O2 SEXP_USE_DL=0 EXE=.bc SO=.bc STATICFLAGS=-shared CPPFLAGS="-DSEXP_USE_STRICT_TOPLEVEL_BINDINGS=1 -DSEXP_USE_ALIGNED_BYTECODE=1 -DSEXP_USE_STATIC_LIBS=1 -DSEXP_USE_STATIC_LIBS_NO_INCLUDE=0" clibs.c chibi-scheme-static.bc VERBOSE=1

chibi-scheme-emscripten: VERSION
	$(MAKE) distclean
	$(MAKE) chibi-scheme-static PLATFORM=emscripten SEXP_USE_DL=0
	(tempfile="`mktemp -t chibi.XXXXXX`" && \
	mv chibi-scheme-static$(EXE) "$$tempfile" && \
	$(MAKE) distclean; \
	mv "$$tempfile" chibi-scheme-emscripten)

include/chibi/install.h: Makefile.libs Makefile.detect
	echo '#define sexp_so_extension "'$(SO)'"' > $@
	echo '#define sexp_default_module_path "'$(MODDIR):$(BINMODDIR):$(SNOWMODDIR):$(SNOWBINMODDIR)'"' >> $@
	echo '#define sexp_platform "'$(PLATFORM)'"' >> $@
	echo '#define sexp_architecture "'$(ARCH)'"' >> $@
	echo '#define sexp_version "'$(CHIBI_VERSION)'"' >> $@
	echo '#define sexp_release_name "'`cat RELEASE`'"' >> $@

lib/chibi/snow/install.sld: Makefile.libs Makefile.detect
	echo '(define-library (chibi snow install)' > $@
	echo '  (import (scheme base))' >> $@
	echo '  (export snow-module-directory snow-binary-module-directory)' >> $@
	echo '  (begin' >> $@
	echo '   (define snow-module-directory "'$(SNOWMODDIR)'")' >> $@
	echo '   (define snow-binary-module-directory "'$(SNOWBINMODDIR)'")))' >> $@

%.o: %.c $(BASE_INCLUDES)
	$(CC) -c $(XCPPFLAGS) $(XCFLAGS) $(CLIBFLAGS) -o $@ $<

gc-ulimit.o: gc.c $(BASE_INCLUDES)
	$(CC) -c $(XCPPFLAGS) $(XCFLAGS) $(CLIBFLAGS) -DSEXP_USE_LIMITED_MALLOC -o $@ $<

sexp-ulimit.o: sexp.c $(BASE_INCLUDES)
	$(CC) -c $(XCPPFLAGS) $(XCFLAGS) $(CLIBFLAGS) -DSEXP_USE_LIMITED_MALLOC -o $@ $<

main.o: main.c $(INCLUDES)
	$(CC) -c $(XCPPFLAGS) $(XCFLAGS) -o $@ $<

SEXP_OBJS = gc.o sexp.o bignum.o gc_heap.o
SEXP_ULIMIT_OBJS = gc-ulimit.o sexp-ulimit.o bignum.o gc_heap.o
EVAL_OBJS = opcodes.o vm.o eval.o simplify.o

libchibi-sexp$(SO): $(SEXP_OBJS)
	$(CC) $(CLIBFLAGS) $(CLINKFLAGS) -o $@ $^ $(XLDFLAGS)

libchibi-scheme$(SO_VERSIONED_SUFFIX): $(SEXP_OBJS) $(EVAL_OBJS)
	$(CC) $(CLIBFLAGS) $(CLINKFLAGS) $(LIBCHIBI_FLAGS) -o $@ $^ $(XLDFLAGS)

libchibi-scheme$(SO_MAJOR_VERSIONED_SUFFIX): libchibi-scheme$(SO_VERSIONED_SUFFIX)
	$(LN) $< $@

libchibi-scheme$(SO): libchibi-scheme$(SO_MAJOR_VERSIONED_SUFFIX)
	$(LN) $< $@

libchibi-scheme.a: $(SEXP_OBJS) $(EVAL_OBJS)
	$(AR) rcs $@ $^

chibi-scheme$(EXE): main.o libchibi-scheme$(SO)
	$(CC) $(XCPPFLAGS) $(XCFLAGS) $(LDFLAGS) -o $@ $< -L. $(RLDFLAGS) -lchibi-scheme

chibi-scheme-static$(EXE): main.o $(SEXP_OBJS) $(EVAL_OBJS)
	$(CC) $(XCFLAGS) $(STATICFLAGS) -o $@ $^ $(LDFLAGS) $(GCLDFLAGS) $(STATIC_LDFLAGS)

chibi-scheme-ulimit$(EXE): main.o $(SEXP_ULIMIT_OBJS) $(EVAL_OBJS)
	$(CC) $(XCFLAGS) $(STATICFLAGS) -o $@ $^ $(LDFLAGS) $(GCLDFLAGS) $(STATIC_LDFLAGS)

clibs.c: $(GENSTATIC) $(CHIBI_DEPENDENCIES) $(COMPILED_LIBS:%$(SO)=%.c)
	if [ -d .git ]; then \
		$(GIT) ls-files lib | $(GREP) .sld | $(CHIBI) -q $(GENSTATIC) > $@; \
	else \
		$(FIND) lib -name \*.sld | $(CHIBI) -q $(GENSTATIC) > $@; \
	fi

chibi-scheme.pc: chibi-scheme.pc.in
	echo "# pkg-config" > chibi-scheme.pc
	echo "prefix=$(PREFIX)" >> chibi-scheme.pc
	echo "exec_prefix=\$${prefix}" >> chibi-scheme.pc
	echo "libdir=$(LIBDIR)" >> chibi-scheme.pc
	echo "includedir=\$${prefix}/include" >> chibi-scheme.pc
	echo "version=$(CHIBI_VERSION)" >> chibi-scheme.pc
	echo "" >> chibi-scheme.pc
	cat chibi-scheme.pc.in >> chibi-scheme.pc

# A special case, this needs to be linked with the LDFLAGS in case
# we're using Boehm.
lib/chibi/ast$(SO): lib/chibi/ast.c $(INCLUDES) libchibi-scheme$(SO)
	-$(CC) $(CLIBFLAGS) $(CLINKFLAGS) $(XCPPFLAGS) $(XCFLAGS) $(LDFLAGS) -o $@ $< $(GCLDFLAGS) -L. $(RLDFLAGS) -lchibi-scheme

lib/chibi/crypto/crypto.c: lib/chibi/crypto/sha2.c
lib/chibi/filesystem.c: lib/chibi/filesystem_win32_shim.c
lib/chibi/io/io.c: lib/chibi/io/port.c
lib/chibi/net.c: lib/chibi/accept.c
lib/chibi/process.c: lib/chibi/signal.c
lib/srfi/144/math.c: lib/srfi/144/lgamma_r.c

lib/chibi.img: $(CHIBI_DEPENDENCIES) all-libs
	$(CHIBI) -d $@

lib/snow.img: $(CHIBI_DEPENDENCIES) all-libs
	$(CHIBI) -mchibi.snow.commands -d $@

lib/red.img: $(CHIBI_DEPENDENCIES) all-libs
	$(CHIBI) -xscheme.red -mchibi.repl -d $@

doc: doc/chibi.html doc-libs

%.html: %.scrbl $(CHIBI_DOC_DEPENDENCIES)
	$(CHIBI_DOC) --html $< > $@

lib/.%.meta: lib/%/ tools/generate-install-meta.scm $(CHIBI_DEPENDENCIES)
	-$(FIND) $< -name \*.sld | \
	 $(CHIBI) tools/generate-install-meta.scm $(CHIBI_VERSION) > $@

########################################################################
# Dist builds - rules to build generated files included in distribution
# (currently just char-sets since it takes a long time and we don't want
# to bundle the raw Unicode files or require a net connection to build).

data/%.txt:
	curl --silent http://www.unicode.org/Public/UNIDATA/$*.txt > $@

build-lib/chibi/char-set/derived.scm: data/UnicodeData.txt data/DerivedCoreProperties.txt chibi-scheme$(EXE)
	$(CHIBI) tools/extract-unicode-props.scm --default > $@

build-lib/chibi/char-set/width.scm: data/UnicodeData.txt data/EastAsianWidth.txt chibi-scheme$(EXE)
	$(CHIBI) tools/extract-unicode-props.scm Zero-Width=Mn > $@
	$(CHIBI) tools/extract-unicode-props.scm -d data/EastAsianWidth.txt Full-Width=F@1,W@1 Ambiguous-Width=A@1 >> $@

lib/chibi/char-set/ascii.scm: build-lib/chibi/char-set/derived.scm chibi-scheme$(EXE)
	$(CHIBI) -Abuild-lib tools/optimize-char-sets.scm --ascii chibi.char-set.compute > $@

lib/chibi/char-set/full.scm: build-lib/chibi/char-set/derived.scm chibi-scheme$(EXE)
	$(CHIBI) -Abuild-lib tools/optimize-char-sets.scm chibi.char-set.compute > $@

lib/chibi/show/width.scm: build-lib/chibi/char-set/width.scm chibi-scheme$(EXE)
	$(CHIBI) -Abuild-lib tools/optimize-char-sets.scm --predicate chibi.char-set.width > $@

lib/scheme/char/case-offsets.scm: data/UnicodeData.txt data/CaseFolding.txt chibi-scheme$(EXE) all-libs
	$(CHIBI) tools/extract-case-offsets.scm data/UnicodeData.txt data/CaseFolding.txt > $@

# WARNING: this has a line for ß added by hand
lib/scheme/char/special-casing.scm: data/CaseFolding.txt data/SpecialCasing.txt chibi-scheme$(EXE) all-libs
	$(CHIBI) tools/extract-special-casing.scm data/CaseFolding.txt data/SpecialCasing.txt > $@

########################################################################
# Tests

checkdefs:
	@for d in $(D); do \
	    if ! $(GREP) -q " SEXP_USE_$${d%%=*} " include/chibi/features.h; then \
		echo "WARNING: unknown definition $$d"; \
	    fi; \
	done

test-basic: chibi-scheme$(EXE)
	@for f in tests/basic/*.scm; do \
	    $(CHIBI) -xchibi $$f >$${f%.scm}.out 2>$${f%.scm}.err; \
	    if $(DIFF) -q $(DIFFOPTS) $${f%.scm}.out $${f%.scm}.res; then \
		echo "[PASS] $${f%.scm}"; \
	    else \
		echo "[FAIL] $${f%.scm}"; \
	    fi; \
	done

test-memory: chibi-scheme-ulimit$(EXE)
	./tests/memory/memory-tests.sh

test-build:
	MAKE=$(MAKE) ./tests/build/build-tests.sh

test-run:
	./tests/run/command-line-tests.sh

test-ffi: chibi-scheme$(EXE)
	$(CHIBI) tests/ffi/ffi-tests.scm

test-snow: chibi-scheme$(EXE) $(IMAGE_FILES)
	$(CHIBI) tests/snow/snow-tests.scm

test-unicode: chibi-scheme$(EXE)
	$(CHIBI) -xchibi tests/unicode-tests.scm

test-division: chibi-scheme$(EXE)
	$(CHIBI) tests/division-tests.scm

test-libs: chibi-scheme$(EXE)
	@echo "\e[1mloading tests first, it may take a while to see output...\e[0m"
	$(CHIBI) tests/lib-tests.scm

test-r5rs: chibi-scheme$(EXE)
	$(CHIBI) -xchibi tests/r5rs-tests.scm

test-r7rs: chibi-scheme$(EXE)
	$(CHIBI) tests/r7rs-tests.scm

test-syntax: chibi-scheme$(EXE)
	$(CHIBI) tests/syntax-tests.scm

test: test-r7rs

test-safe-string-cursors: chibi-scheme$(EXE)
	$(CHIBI) -Dsafe-string-cursors tests/r7rs-tests.scm
	$(CHIBI) -Dsafe-string-cursors tests/lib-tests.scm

test-all: test test-syntax test-libs test-ffi test-division

test-dist: test-all test-memory test-build

bench-gabriel: chibi-scheme$(EXE)
	./benchmarks/gabriel/run.sh

########################################################################
# Packaging

clean: clean-libs
	-$(RM) *.o *.i *.s *.bc *.8 tests/basic/*.out tests/basic/*.err \
	    tests/run/*.out tests/run/*.err

cleaner: clean
	-$(RM) chibi-scheme$(EXE) chibi-scheme-static$(EXE) chibi-scheme-ulimit$(EXE) \
	    $(IMAGE_FILES) libchibi-scheme*$(SO) *.a *.pc \
	    libchibi-scheme$(SO_VERSIONED_SUFFIX) \
	    libchibi-scheme$(SO_MAJOR_VERSIONED_SUFFIX) \
	    include/chibi/install.h lib/.*.meta \
	    chibi-scheme-emscripten \
	    js/chibi.* \
	    $(shell $(FIND) lib -name \*.o)

distclean: dist-clean-libs cleaner
dist-clean: distclean

install-base: all
	$(MKDIR) $(DESTDIR)$(BINDIR)
	$(INSTALL_EXE) -m0755 chibi-scheme$(EXE) $(DESTDIR)$(BINDIR)/
	$(INSTALL) -m0755 tools/chibi-ffi $(DESTDIR)$(BINDIR)/
	$(INSTALL) -m0755 tools/chibi-doc $(DESTDIR)$(BINDIR)/
	$(INSTALL) -m0755 tools/snow-chibi $(DESTDIR)$(BINDIR)/
	$(INSTALL) -m0755 tools/snow-chibi.scm $(DESTDIR)$(BINDIR)/
	$(MKDIR) $(DESTDIR)$(MODDIR)/chibi/char-set $(DESTDIR)$(MODDIR)/chibi/crypto $(DESTDIR)$(MODDIR)/chibi/io $(DESTDIR)$(MODDIR)/chibi/iset $(DESTDIR)$(MODDIR)/chibi/loop $(DESTDIR)$(MODDIR)/chibi/match $(DESTDIR)$(MODDIR)/chibi/math $(DESTDIR)$(MODDIR)/chibi/monad $(DESTDIR)$(MODDIR)/chibi/net $(DESTDIR)$(MODDIR)/chibi/optimize $(DESTDIR)$(MODDIR)/chibi/parse $(DESTDIR)$(MODDIR)/chibi/regexp $(DESTDIR)$(MODDIR)/chibi/show $(DESTDIR)$(MODDIR)/chibi/snow $(DESTDIR)$(MODDIR)/chibi/term $(DESTDIR)$(MODDIR)/chibi/text
	$(MKDIR) $(DESTDIR)$(MODDIR)/scheme/char
	$(MKDIR) $(DESTDIR)$(MODDIR)/scheme/time
	$(MKDIR) $(DESTDIR)$(MODDIR)/srfi/1 $(DESTDIR)$(MODDIR)/srfi/18 $(DESTDIR)$(MODDIR)/srfi/27 $(DESTDIR)$(MODDIR)/srfi/151 $(DESTDIR)$(MODDIR)/srfi/39 $(DESTDIR)$(MODDIR)/srfi/69 $(DESTDIR)$(MODDIR)/srfi/95 $(DESTDIR)$(MODDIR)/srfi/99 $(DESTDIR)$(MODDIR)/srfi/99/records $(DESTDIR)$(MODDIR)/srfi/113 $(DESTDIR)$(MODDIR)/srfi/117 $(DESTDIR)$(MODDIR)/srfi/121 $(DESTDIR)$(MODDIR)/srfi/125 $(DESTDIR)$(MODDIR)/srfi/128 $(DESTDIR)$(MODDIR)/srfi/129 $(DESTDIR)$(MODDIR)/srfi/132 $(DESTDIR)$(MODDIR)/srfi/133 $(DESTDIR)$(MODDIR)/srfi/135 $(DESTDIR)$(MODDIR)/srfi/143 $(DESTDIR)$(MODDIR)/srfi/144 $(DESTDIR)$(MODDIR)/srfi/159 $(DESTDIR)$(MODDIR)/srfi/160 $(DESTDIR)$(MODDIR)/srfi/166 $(DESTDIR)$(MODDIR)/srfi/146 $(DESTDIR)$(MODDIR)/srfi/179 $(DESTDIR)$(MODDIR)/srfi/211 $(DESTDIR)$(MODDIR)/srfi/231
	$(INSTALL) -m0644 $(META_FILES) $(DESTDIR)$(MODDIR)/
	$(INSTALL) -m0644 lib/*.scm $(DESTDIR)$(MODDIR)/
	$(INSTALL) -m0644 lib/chibi/*.sld lib/chibi/*.scm $(DESTDIR)$(MODDIR)/chibi/
	$(INSTALL) -m0644 lib/chibi/char-set/*.sld lib/chibi/char-set/*.scm $(DESTDIR)$(MODDIR)/chibi/char-set/
	$(INSTALL) -m0644 lib/chibi/crypto/*.sld lib/chibi/crypto/*.scm $(DESTDIR)$(MODDIR)/chibi/crypto/
	$(INSTALL) -m0644 lib/chibi/io/*.scm $(DESTDIR)$(MODDIR)/chibi/io/
	$(INSTALL) -m0644 lib/chibi/iset/*.sld lib/chibi/iset/*.scm $(DESTDIR)$(MODDIR)/chibi/iset/
	$(INSTALL) -m0644 lib/chibi/loop/*.scm $(DESTDIR)$(MODDIR)/chibi/loop/
	$(INSTALL) -m0644 lib/chibi/match/*.scm $(DESTDIR)$(MODDIR)/chibi/match/
	$(INSTALL) -m0644 lib/chibi/math/*.sld lib/chibi/math/*.scm $(DESTDIR)$(MODDIR)/chibi/math/
	$(INSTALL) -m0644 lib/chibi/monad/*.sld lib/chibi/monad/*.scm $(DESTDIR)$(MODDIR)/chibi/monad/
	$(INSTALL) -m0644 lib/chibi/net/*.sld lib/chibi/net/*.scm $(DESTDIR)$(MODDIR)/chibi/net/
	$(INSTALL) -m0644 lib/chibi/optimize/*.sld lib/chibi/optimize/*.scm $(DESTDIR)$(MODDIR)/chibi/optimize/
	$(INSTALL) -m0644 lib/chibi/parse/*.sld lib/chibi/parse/*.scm $(DESTDIR)$(MODDIR)/chibi/parse/
	$(INSTALL) -m0644 lib/chibi/regexp/*.sld lib/chibi/regexp/*.scm $(DESTDIR)$(MODDIR)/chibi/regexp/
	$(INSTALL) -m0644 lib/chibi/show/*.sld lib/chibi/show/*.scm $(DESTDIR)$(MODDIR)/chibi/show/
	$(INSTALL) -m0644 lib/chibi/snow/*.sld lib/chibi/snow/*.scm $(DESTDIR)$(MODDIR)/chibi/snow/
	$(INSTALL) -m0644 lib/chibi/term/*.sld lib/chibi/term/*.scm $(DESTDIR)$(MODDIR)/chibi/term/
	$(INSTALL) -m0644 lib/chibi/text/*.sld lib/chibi/text/*.scm $(DESTDIR)$(MODDIR)/chibi/text/
	$(INSTALL) -m0644 lib/scheme/*.sld lib/scheme/*.scm $(DESTDIR)$(MODDIR)/scheme/
	$(INSTALL) -m0644 lib/scheme/char/*.sld lib/scheme/char/*.scm $(DESTDIR)$(MODDIR)/scheme/char/
	$(INSTALL) -m0644 lib/scheme/time/*.sld $(DESTDIR)$(MODDIR)/scheme/time/
	$(INSTALL) -m0644 lib/srfi/*.sld lib/srfi/*.scm $(DESTDIR)$(MODDIR)/srfi/
	$(INSTALL) -m0644 lib/srfi/1/*.sld $(DESTDIR)$(MODDIR)/srfi/1/
	$(INSTALL) -m0644 lib/srfi/1/*.scm $(DESTDIR)$(MODDIR)/srfi/1/
	$(INSTALL) -m0644 lib/srfi/18/*.scm $(DESTDIR)$(MODDIR)/srfi/18/
	$(INSTALL) -m0644 lib/srfi/27/*.scm $(DESTDIR)$(MODDIR)/srfi/27/
	$(INSTALL) -m0644 lib/srfi/39/*.scm $(DESTDIR)$(MODDIR)/srfi/39/
	$(INSTALL) -m0644 lib/srfi/69/*.scm $(DESTDIR)$(MODDIR)/srfi/69/
	$(INSTALL) -m0644 lib/srfi/95/*.scm $(DESTDIR)$(MODDIR)/srfi/95/
	$(INSTALL) -m0644 lib/srfi/99/*.sld $(DESTDIR)$(MODDIR)/srfi/99/
	$(INSTALL) -m0644 lib/srfi/99/records/*.sld lib/srfi/99/records/*.scm $(DESTDIR)$(MODDIR)/srfi/99/records/
	$(INSTALL) -m0644 lib/srfi/113/*.scm $(DESTDIR)$(MODDIR)/srfi/113/
	$(INSTALL) -m0644 lib/srfi/117/*.scm $(DESTDIR)$(MODDIR)/srfi/117/
	$(INSTALL) -m0644 lib/srfi/121/*.scm $(DESTDIR)$(MODDIR)/srfi/121/
	$(INSTALL) -m0644 lib/srfi/125/*.scm $(DESTDIR)$(MODDIR)/srfi/125/
	$(INSTALL) -m0644 lib/srfi/128/*.scm $(DESTDIR)$(MODDIR)/srfi/128/
	$(INSTALL) -m0644 lib/srfi/129/*.scm $(DESTDIR)$(MODDIR)/srfi/129/
	$(INSTALL) -m0644 lib/srfi/132/*.scm $(DESTDIR)$(MODDIR)/srfi/132/
	$(INSTALL) -m0644 lib/srfi/133/*.scm $(DESTDIR)$(MODDIR)/srfi/133/
	$(INSTALL) -m0644 lib/srfi/135/*.sld lib/srfi/135/*.scm $(DESTDIR)$(MODDIR)/srfi/135/
	$(INSTALL) -m0644 lib/srfi/143/*.scm $(DESTDIR)$(MODDIR)/srfi/143/
	$(INSTALL) -m0644 lib/srfi/144/*.scm $(DESTDIR)$(MODDIR)/srfi/144/
	$(INSTALL) -m0644 lib/srfi/151/*.scm $(DESTDIR)$(MODDIR)/srfi/151/
	$(INSTALL) -m0644 lib/srfi/159/*.scm $(DESTDIR)$(MODDIR)/srfi/159/
	$(INSTALL) -m0644 lib/srfi/159/*.sld $(DESTDIR)$(MODDIR)/srfi/159/
	$(INSTALL) -m0644 lib/srfi/160/*.sld $(DESTDIR)$(MODDIR)/srfi/160/
	$(INSTALL) -m0644 lib/srfi/160/*.scm $(DESTDIR)$(MODDIR)/srfi/160/
	$(INSTALL) -m0644 lib/srfi/166/*.sld $(DESTDIR)$(MODDIR)/srfi/166/
	$(INSTALL) -m0644 lib/srfi/166/*.scm $(DESTDIR)$(MODDIR)/srfi/166/
	$(INSTALL) -m0644 lib/srfi/146/*.sld $(DESTDIR)$(MODDIR)/srfi/146/
	$(INSTALL) -m0644 lib/srfi/146/*.scm $(DESTDIR)$(MODDIR)/srfi/146/
	$(INSTALL) -m0644 lib/srfi/179/*.sld $(DESTDIR)$(MODDIR)/srfi/179/
	$(INSTALL) -m0644 lib/srfi/179/*.scm $(DESTDIR)$(MODDIR)/srfi/179/
	$(INSTALL) -m0644 lib/srfi/211/*.sld $(DESTDIR)$(MODDIR)/srfi/211/
	$(INSTALL) -m0644 lib/srfi/231/*.sld lib/srfi/231/*.scm $(DESTDIR)$(MODDIR)/srfi/231/
	$(MKDIR) $(DESTDIR)$(BINMODDIR)/chibi/crypto/
	$(MKDIR) $(DESTDIR)$(BINMODDIR)/chibi/io/
	$(MKDIR) $(DESTDIR)$(BINMODDIR)/chibi/optimize/
	$(MKDIR) $(DESTDIR)$(BINMODDIR)/scheme/
	$(MKDIR) $(DESTDIR)$(BINMODDIR)/srfi/18 $(DESTDIR)$(BINMODDIR)/srfi/27 $(DESTDIR)$(BINMODDIR)/srfi/151 $(DESTDIR)$(BINMODDIR)/srfi/39 $(DESTDIR)$(BINMODDIR)/srfi/69 $(DESTDIR)$(BINMODDIR)/srfi/95 $(DESTDIR)$(BINMODDIR)/srfi/98 $(DESTDIR)$(BINMODDIR)/srfi/144 $(DESTDIR)$(BINMODDIR)/srfi/160
	$(INSTALL_EXE) -m0755 $(CHIBI_COMPILED_LIBS) $(DESTDIR)$(BINMODDIR)/chibi/
	$(INSTALL_EXE) -m0755 $(CHIBI_CRYPTO_COMPILED_LIBS) $(DESTDIR)$(BINMODDIR)/chibi/crypto/
	$(INSTALL_EXE) -m0755 $(CHIBI_IO_COMPILED_LIBS) $(DESTDIR)$(BINMODDIR)/chibi/io/
	$(INSTALL_EXE) -m0755 $(CHIBI_OPT_COMPILED_LIBS) $(DESTDIR)$(BINMODDIR)/chibi/optimize/
	$(INSTALL_EXE) -m0755 lib/scheme/time$(SO) $(DESTDIR)$(BINMODDIR)/scheme/
	$(INSTALL_EXE) -m0755 lib/scheme/bytevector$(SO) $(DESTDIR)$(BINMODDIR)/scheme/
	$(INSTALL_EXE) -m0755 lib/srfi/18/threads$(SO) $(DESTDIR)$(BINMODDIR)/srfi/18
	$(INSTALL_EXE) -m0755 lib/srfi/27/rand$(SO) $(DESTDIR)$(BINMODDIR)/srfi/27
	$(INSTALL_EXE) -m0755 lib/srfi/39/param$(SO) $(DESTDIR)$(BINMODDIR)/srfi/39
	$(INSTALL_EXE) -m0755 lib/srfi/69/hash$(SO) $(DESTDIR)$(BINMODDIR)/srfi/69
	$(INSTALL_EXE) -m0755 lib/srfi/95/qsort$(SO) $(DESTDIR)$(BINMODDIR)/srfi/95
	$(INSTALL_EXE) -m0755 lib/srfi/98/env$(SO) $(DESTDIR)$(BINMODDIR)/srfi/98
	$(INSTALL_EXE) -m0755 lib/srfi/144/math$(SO) $(DESTDIR)$(BINMODDIR)/srfi/144
	$(INSTALL_EXE) -m0755 lib/srfi/151/bit$(SO) $(DESTDIR)$(BINMODDIR)/srfi/151
	$(INSTALL_EXE) -m0755 lib/srfi/160/uvprims$(SO) $(DESTDIR)$(BINMODDIR)/srfi/160
	$(MKDIR) $(DESTDIR)$(INCDIR)
	$(INSTALL) -m0644 $(INCLUDES) $(DESTDIR)$(INCDIR)/
	$(MKDIR) $(DESTDIR)$(LIBDIR)
	$(MKDIR) $(DESTDIR)$(SOLIBDIR)
	$(INSTALL_EXE) -m0755 libchibi-scheme$(SO_VERSIONED_SUFFIX) $(DESTDIR)$(SOLIBDIR)/
	$(LN) libchibi-scheme$(SO_VERSIONED_SUFFIX) $(DESTDIR)$(SOLIBDIR)/libchibi-scheme$(SO_MAJOR_VERSIONED_SUFFIX)
	$(LN) libchibi-scheme$(SO_VERSIONED_SUFFIX) $(DESTDIR)$(SOLIBDIR)/libchibi-scheme$(SO)
	-if test -f libchibi-scheme.a; then $(INSTALL) -m0644 libchibi-scheme.a $(DESTDIR)$(SOLIBDIR)/; fi
	$(MKDIR) $(DESTDIR)$(PKGCONFDIR)
	$(INSTALL) -m0644 chibi-scheme.pc $(DESTDIR)$(PKGCONFDIR)
	$(MKDIR) $(DESTDIR)$(MANDIR)
	$(INSTALL) -m0644 doc/chibi-scheme.1 $(DESTDIR)$(MANDIR)/
	$(INSTALL) -m0644 doc/chibi-ffi.1 $(DESTDIR)$(MANDIR)/
	$(INSTALL) -m0644 doc/chibi-doc.1 $(DESTDIR)$(MANDIR)/
	-if type $(LDCONFIG) >/dev/null 2>/dev/null; then $(LDCONFIG) >/dev/null 2>/dev/null; fi

install-bash-completion:
	if [ -d "/etc/bash_completion.d" ]; then \
			cp tools/snow-chibi-completion.bash /etc/bash_completion.d/snow-chibi; \
		fi

install: install-base install-bash-completion
ifneq "$(IMAGE_FILES)" ""
	echo "Generating images"
	-[ -z "$(DESTDIR)" ] && LD_LIBRARY_PATH="$(SOLIBDIR):$(LD_LIBRARY_PATH)" DYLD_LIBRARY_PATH="$(SOLIBDIR):$(DYLD_LIBRARY_PATH)" CHIBI_MODULE_PATH="$(MODDIR):$(BINMODDIR)" $(BINDIR)/chibi-scheme$(EXE) -mchibi.repl -d $(MODDIR)/chibi.img
	-[ -z "$(DESTDIR)" ] && LD_LIBRARY_PATH="$(SOLIBDIR):$(LD_LIBRARY_PATH)" DYLD_LIBRARY_PATH="$(SOLIBDIR):$(DYLD_LIBRARY_PATH)" CHIBI_MODULE_PATH="$(MODDIR):$(BINMODDIR)" $(BINDIR)/chibi-scheme$(EXE) -xscheme.red -mchibi.repl -d $(MODDIR)/red.img
	-[ -z "$(DESTDIR)" ] && LD_LIBRARY_PATH="$(SOLIBDIR):$(LD_LIBRARY_PATH)" DYLD_LIBRARY_PATH="$(SOLIBDIR):$(DYLD_LIBRARY_PATH)" CHIBI_MODULE_PATH="$(MODDIR):$(BINMODDIR)" $(BINDIR)/chibi-scheme$(EXE) -mchibi.snow.commands -mchibi.snow.interface -mchibi.snow.package -mchibi.snow.utils -d $(DESTDIR)$(MODDIR)/snow.img
endif

uninstall:
	-$(RM) $(DESTDIR)$(BINDIR)/chibi-scheme$(EXE)
	-$(RM) $(DESTDIR)$(BINDIR)/chibi-scheme-static$(EXE)
	-$(RM) $(DESTDIR)$(BINDIR)/chibi-ffi
	-$(RM) $(DESTDIR)$(BINDIR)/chibi-doc
	-$(RM) $(DESTDIR)$(BINDIR)/snow-chibi
	-$(RM) $(DESTDIR)$(BINDIR)/snow-chibi.scm
	-$(RM) $(DESTDIR)$(SOLIBDIR)/libchibi-scheme$(SO)
	-$(RM) $(DESTDIR)$(SOLIBDIR)/libchibi-scheme$(SO_VERSIONED_SUFFIX)
	-$(RM) $(DESTDIR)$(SOLIBDIR)/libchibi-scheme$(SO_MAJOR_VERSIONED_SUFFIX)
	-$(RM) $(DESTDIR)$(LIBDIR)/libchibi-scheme$(SO).a
	-$(RM) $(DESTDIR)$(PKGCONFDIR)/chibi-scheme.pc
	-$(CD) $(DESTDIR)$(PREFIX) && $(RM) $(INCLUDES)
	-$(RMDIR) $(DESTDIR)$(INCDIR)
	-$(RM) $(DESTDIR)$(MODDIR)/srfi/99/records/*.sld
	-$(RM) $(DESTDIR)$(MODDIR)/srfi/99/records/*.scm
	-$(RM) $(DESTDIR)$(MODDIR)/.*.meta
	-$(RM) $(DESTDIR)$(MODDIR)/*.img
	-$(RM) $(DESTDIR)$(MODDIR)/*.sld $(DESTDIR)$(MODDIR)/*/*.sld $(DESTDIR)$(MODDIR)/*/*/*.sld
	-$(RM) $(DESTDIR)$(MODDIR)/*.scm $(DESTDIR)$(MODDIR)/*/*.scm $(DESTDIR)$(MODDIR)/*/*/*.scm
	-$(CD) $(DESTDIR)$(MODDIR) && $(RM) $(COMPILED_LIBS:lib/%=%)
	-$(CD) $(DESTDIR)$(BINMODDIR) && $(RM) $(COMPILED_LIBS:lib/%=%)
	-$(RMDIR) $(DESTDIR)$(MODDIR)/chibi/char-set $(DESTDIR)$(BINMODDIR)/chibi/char-set
	-$(RMDIR) $(DESTDIR)$(MODDIR)/chibi/crypto $(DESTDIR)$(BINMODDIR)/chibi/crypto
	-$(RMDIR) $(DESTDIR)$(MODDIR)/chibi/io $(DESTDIR)$(BINMODDIR)/chibi/io
	-$(RMDIR) $(DESTDIR)$(MODDIR)/chibi/iset $(DESTDIR)$(BINMODDIR)/chibi/iset
	-$(RMDIR) $(DESTDIR)$(MODDIR)/chibi/loop $(DESTDIR)$(BINMODDIR)/chibi/loop
	-$(RMDIR) $(DESTDIR)$(MODDIR)/chibi/match $(DESTDIR)$(BINMODDIR)/chibi/match
	-$(RMDIR) $(DESTDIR)$(MODDIR)/chibi/math $(DESTDIR)$(BINMODDIR)/chibi/math
	-$(RMDIR) $(DESTDIR)$(MODDIR)/chibi/monad $(DESTDIR)$(BINMODDIR)/chibi/monad
	-$(RMDIR) $(DESTDIR)$(MODDIR)/chibi/net $(DESTDIR)$(BINMODDIR)/chibi/net
	-$(RMDIR) $(DESTDIR)$(MODDIR)/chibi/optimize $(DESTDIR)$(BINMODDIR)/chibi/optimize
	-$(RMDIR) $(DESTDIR)$(MODDIR)/chibi/parse $(DESTDIR)$(BINMODDIR)/chibi/parse
	-$(RMDIR) $(DESTDIR)$(MODDIR)/chibi/regexp $(DESTDIR)$(BINMODDIR)/chibi/regexp
	-$(RMDIR) $(DESTDIR)$(MODDIR)/chibi/show $(DESTDIR)$(BINMODDIR)/chibi/show
	-$(RMDIR) $(DESTDIR)$(MODDIR)/chibi/snow $(DESTDIR)$(BINMODDIR)/chibi/snow
	-$(RMDIR) $(DESTDIR)$(MODDIR)/chibi/term $(DESTDIR)$(BINMODDIR)/chibi/term
	-$(RMDIR) $(DESTDIR)$(MODDIR)/chibi/text $(DESTDIR)$(BINMODDIR)/chibi/text
	-$(RMDIR) $(DESTDIR)$(MODDIR)/chibi $(DESTDIR)$(BINMODDIR)/chibi
	-$(RMDIR) $(DESTDIR)$(MODDIR)/scheme/char $(DESTDIR)$(BINMODDIR)/scheme/char
	-$(RMDIR) $(DESTDIR)$(MODDIR)/scheme/time $(DESTDIR)$(BINMODDIR)/scheme/time
	-$(RMDIR) $(DESTDIR)$(MODDIR)/scheme $(DESTDIR)$(BINMODDIR)/scheme
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/1 $(DESTDIR)$(BINMODDIR)/srfi/1
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/18 $(DESTDIR)$(BINMODDIR)/srfi/18
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/27 $(DESTDIR)$(BINMODDIR)/srfi/27
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/39 $(DESTDIR)$(BINMODDIR)/srfi/39
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/69 $(DESTDIR)$(BINMODDIR)/srfi/69
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/95 $(DESTDIR)$(BINMODDIR)/srfi/95
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/98 $(DESTDIR)$(BINMODDIR)/srfi/98
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/99/records $(DESTDIR)$(BINMODDIR)/srfi/99/records
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/99 $(DESTDIR)$(BINMODDIR)/srfi/99
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/113 $(DESTDIR)$(BINMODDIR)/srfi/113
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/117 $(DESTDIR)$(BINMODDIR)/srfi/117
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/121 $(DESTDIR)$(BINMODDIR)/srfi/121
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/125 $(DESTDIR)$(BINMODDIR)/srfi/125
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/128 $(DESTDIR)$(BINMODDIR)/srfi/128
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/129 $(DESTDIR)$(BINMODDIR)/srfi/129
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/132 $(DESTDIR)$(BINMODDIR)/srfi/132
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/133 $(DESTDIR)$(BINMODDIR)/srfi/133
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/135 $(DESTDIR)$(BINMODDIR)/srfi/135
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/143 $(DESTDIR)$(BINMODDIR)/srfi/143
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/151 $(DESTDIR)$(BINMODDIR)/srfi/151
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/144 $(DESTDIR)$(BINMODDIR)/srfi/144
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/146 $(DESTDIR)$(BINMODDIR)/srfi/146
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/159 $(DESTDIR)$(BINMODDIR)/srfi/159
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/160 $(DESTDIR)$(BINMODDIR)/srfi/160
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/166 $(DESTDIR)$(BINMODDIR)/srfi/166
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/179 $(DESTDIR)$(BINMODDIR)/srfi/179
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/211 $(DESTDIR)$(BINMODDIR)/srfi/211
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi/231 $(DESTDIR)$(BINMODDIR)/srfi/231
	-$(RMDIR) $(DESTDIR)$(MODDIR)/srfi $(DESTDIR)$(BINMODDIR)/srfi
	-$(RMDIR) $(DESTDIR)$(MODDIR) $(DESTDIR)$(BINMODDIR)
	-$(RM) $(DESTDIR)$(MANDIR)/chibi-scheme.1 $(DESTDIR)$(MANDIR)/chibi-ffi.1 $(DESTDIR)$(MANDIR)/chibi-doc.1
	-$(RM) $(DESTDIR)$(PKGCONFDIR)/chibi-scheme.pc
	-$(RM) /etc/bash_completion.d/snow-chibi

dist: distclean
	$(RM) chibi-scheme-$(CHIBI_VERSION).tgz
	$(MKDIR) chibi-scheme-$(CHIBI_VERSION)
	@for f in `git ls-files | grep -v ^benchmarks/`; do $(MKDIR) chibi-scheme-$(CHIBI_VERSION)/`dirname $$f`; $(SYMLINK) `pwd`/$$f chibi-scheme-$(CHIBI_VERSION)/$$f; done
	$(TAR) cphzvf chibi-scheme-$(CHIBI_VERSION).tgz chibi-scheme-$(CHIBI_VERSION)
	$(RM) -r chibi-scheme-$(CHIBI_VERSION)

mips-dist: distclean
	$(RM) chibi-scheme-`date +%Y%m%d`-`git log HEAD^..HEAD | head -1 | cut -c8-`.tgz
	$(MKDIR) chibi-scheme-`date +%Y%m%d`-`git log HEAD^..HEAD | head -1 | cut -c8-`
	@for f in `git ls-files | grep -v ^benchmarks/`; do $(MKDIR) chibi-scheme-`date +%Y%m%d`-`git log HEAD^..HEAD | head -1 | cut -c8-`/`dirname $$f`; $(SYMLINK) `pwd`/$$f chibi-scheme-`date +%Y%m%d`-`git log HEAD^..HEAD | head -1 | cut -c8-`/$$f; done
	$(TAR) cphzvf chibi-scheme-`date +%Y%m%d`-`git log HEAD^..HEAD | head -1 | cut -c8-`.tgz chibi-scheme-`date +%Y%m%d`-`git log HEAD^..HEAD | head -1 | cut -c8-`
	$(RM) -r chibi-scheme-`date +%Y%m%d`-`git log HEAD^..HEAD | head -1 | cut -c8-`

debian:
	sudo checkinstall -D --pkgname chibi-scheme --pkgversion $(CHIBI_VERSION) --maintainer "http://groups.google.com/group/chibi-scheme" -y make PREFIX=/usr install

# Libraries in the standard distribution we want to make available to
# other Scheme implementations.  Note this is run with my own
# ~/.snow/config.scm, which specifies my own settings regarding
# author, license, extracting docs from scribble, etc.
snowballs:
	$(SNOW_CHIBI) package --license public-domain lib/chibi/char-set/boundary.sld
	$(SNOW_CHIBI) package --license public-domain lib/chibi/match.sld
	$(SNOW_CHIBI) package -r lib/chibi/char-set.sld
	$(SNOW_CHIBI) package -r lib/chibi/iset.sld lib/chibi/iset/optimize.sld
	$(SNOW_CHIBI) package --doc https://srfi.schemers.org/srfi-115/srfi-115.html --test-library lib/srfi/115.sld
	$(SNOW_CHIBI) package -r --doc https://srfi.schemers.org/srfi-166/srfi-166.html --test-library lib/srfi/166/test.sld lib/srfi/166.sld lib/chibi/show/shared.sld
	$(SNOW_CHIBI) package -r --doc https://srfi.schemers.org/srfi-179/srfi-179.html --test-library lib/srfi/179/test.sld lib/srfi/179.sld
	$(SNOW_CHIBI) package lib/chibi/app.sld
	$(SNOW_CHIBI) package lib/chibi/assert.sld
	$(SNOW_CHIBI) package lib/chibi/base64.sld
	$(SNOW_CHIBI) package lib/chibi/binary-record.sld
	$(SNOW_CHIBI) package lib/chibi/bytevector.sld
	$(SNOW_CHIBI) package lib/chibi/config.sld
	$(SNOW_CHIBI) package lib/chibi/crypto/md5.sld
	$(SNOW_CHIBI) package lib/chibi/crypto/rsa.sld
	$(SNOW_CHIBI) package lib/chibi/crypto/sha2.sld
	$(SNOW_CHIBI) package lib/chibi/diff.sld
	$(SNOW_CHIBI) package lib/chibi/edit-distance.sld
	$(SNOW_CHIBI) package lib/chibi/filesystem.sld
	$(SNOW_CHIBI) package lib/chibi/math/prime.sld
	$(SNOW_CHIBI) package lib/chibi/mime.sld
	$(SNOW_CHIBI) package lib/chibi/monad/environment.sld
	$(SNOW_CHIBI) package lib/chibi/optional.sld
	$(SNOW_CHIBI) package lib/chibi/parse.sld lib/chibi/parse/common.sld
	$(SNOW_CHIBI) package lib/chibi/pathname.sld
	$(SNOW_CHIBI) package lib/chibi/quoted-printable.sld
	$(SNOW_CHIBI) package lib/chibi/regexp.sld lib/chibi/regexp/pcre.sld
	$(SNOW_CHIBI) package lib/chibi/scribble.sld
	$(SNOW_CHIBI) package lib/chibi/string.sld
	$(SNOW_CHIBI) package lib/chibi/sxml.sld
	$(SNOW_CHIBI) package lib/chibi/tar.sld
	$(SNOW_CHIBI) package lib/chibi/temp-file.sld
	$(SNOW_CHIBI) package lib/chibi/term/ansi.sld
	$(SNOW_CHIBI) package lib/chibi/term/edit-line.sld
	$(SNOW_CHIBI) package lib/chibi/test.sld
	$(SNOW_CHIBI) package lib/chibi/uri.sld
	$(SNOW_CHIBI) package lib/chibi/zlib.sld
