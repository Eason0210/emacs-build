#!/usr/bin/bash
# package-emacs-master - Create Snapshot Binary Release Packages for Windows
#
# Copyright 2023 Corwin Brust <corwin@bru.st>
#
# This program is distributed under the terms of the GNU Public
# License version 3 or (at your option) any later version.
#

# most likely things to edit
TO=${TO:-/d/emacs-build}
FROM=${FROM:-/c/users/corwi/emacs-build}
MV=${MV:-30}
SRC=${SRC:-$FROM/git/emacs-$MV}
DIR=${DIR:-$TO/template.directive}

# get current the version for the main development branch
SVH_CGIT="https://git.savannah.gnu.org/cgit/emacs.git/plain/configure.ac"
MASTER_VERSION=$(wget -qO - $SVH_CGIT \
		     | grep AC_INIT \
		     | perl -ne 'print $1 if /(\d+\.\d+\.\d+)/');
# get the first component of master's version, for later
MASTER_VERSION_MAJOR_VERSION=$(echo $MASTER_VERSION | cut -d . -f 1)

# and the local version
EV=${EV-$(grep '^AC_INIT' $SRC/configure.ac 2>/dev/null |perl -ne 'print $1 if /(\d+\.\d+\.\d+)/')}

DEPS=${DEPS:-$FROM/deps/emacs-${MV}-deps.zip}
SHORT_VER=${SHORT_VER:-$(cd $SRC; git rev-parse --short=6 HEAD)}
LONG_VER=${LONG_VER:-$(cd $SRC; git rev-parse HEAD)}
SLUG=${SLUG:-${MV}-$SHORT_VER}

EB=${EB:-"emacs-${SLUG}"}
EL=${EL:-"emacs-${EV}-$SHORT_VER"}
IB=${IB:-"${TO}/install"}
IN=${IN:-"${IB}/${EB}"}
UP=${UP:-"${TO}/upload/${EB}"}
NO=${NO:-"${UP}/${EL}-no-deps.zip"}
FU=${FU:-"${UP}/${EL}.zip"}
SZ=${SZ:-"${UP}/${EL}-src.zip"}
SE=${SE:-"${UP}/${EL}-installer.exe"}

OE="${IB}/emacs-${EV}-installer.exe"
SXS=$IB/emacs-${EV:-"${MV}.0.50"}

# we are building when the source branch the same version as master
if [[ $MV -eq $MASTER_VERSION_MAJOR_VERSION ]] ; then
    BRANCH=master
else
    BRANCH=emacs-$MV
fi

echo "SVH: ${SVH_CGIT}
  SV: ${MASTER_VERSION}
  MM: ${MASTER_VERSION_MAJOR_VERSION}
  MV: ${MV}
  BR: ${BRANCH}
  TO: ${TO}
FROM: ${FROM}
 SRC: ${SRC}
DEPS: ${DEPS}
SREV: ${SHORT_VER}
LREV: ${LONG_VER}
SLUG: ${SLUG}
  EB: ${EB}
  IB: ${IB}
  IN: ${IN}
  UP: ${UP}
  NO: ${NO}
  FU: ${FU}
  SZ: ${SZ}
  SE: ${SE}
  OE: ${OE}
 DIR: ${DIR}
  EV: ${EV}
 SXS: ${SXS}"

if [[ -z "$SHORT_VER" ]] ; then
    echo "Failed to extract git revision (short)"
    exit 1;
fi

if [[ -z "$LONG_VER" ]] ; then
    echo "Failed to extract git revision"
    exit 1;
fi

sleep 10;

if [[ -d $IN ]] ; then
    echo "NOTICE: build dir exits: $IN"
else
    (cd $SRC; git clean -fxd;
     ((./autogen.sh \
	   && ./configure --with-modules \
			  --without-dbus \
			  --with-native-compilation \
			  --without-compress-install \
			  --with-tree-sitter \
			  CFLAGS=-O2 \
	   && make install -j 20 \
		   NATIVE_FULL_AOT=1 \
		   prefix=$IN ) |tee $TO/${EB}-make.log
     )  && echo "1..OK make" \
	 && echo "$SHORT_VER	$LONG_VER" > $IN/.git-revision
    ) || (echo "ERROR: prep upload ($?)"; exit 1);
fi

if [[ ! -d $IN ]]; then
    echo "ERROR install folder is missing: $IN"
    exit 1
fi

if [[ -r $NO ]]; then
    echo "NOTICE: no-deps zip exits: $NO"
else
    ((mkdir -p $UP \
	  && cd $IN \
	  && zip -vr9 $NO . 2>&1) \
	 |tee $TO/${EB}-zip-deps.log \
	 && echo "2..OK zip nodeps") \
	|| ( echo "FAILED ($?)" ; exit 2 )
fi

if [[ -r $FU ]]; then
    echo "NOTICE: full zip exists: $FU"
else
    ((cd $IN \
	  && unzip -d bin $DEPS 2>&1) \
	 |tee $TO/${EB}-unzip-deps.log \
	 && echo "3..OK unzip deps") \
	|| ( echo "FAILED ($?)" ; exit 3 )
    ((cd $IN \
	  && zip -vr9 $FU . 2>&1) \
	 |tee $TO/${EB}-zip.log \
	 && echo "4..OK rezip full") \
	|| ( echo "FAILED ($?)" ; exit 4 )
fi

if [[ -r $SE ]] ; then
    echo "NOTICE: self-installer exists: $SE";
else
    sleep 10;
    if [[ -d $SXS ]] ; then
	echo "WARNING: Self-install source dir found, reusing: $SXS";
    else
 	mv $IN $SXS ||
	    ( echo "ERROR: installer source mv failed ($?): $IN => $SXS";
	      exit 5; )
    fi

    ((cd $IB \
	  && cp $SRC/admin/nt/dist-build/emacs.nsi . \
	  && makensis -v4 \
		      -DEMACS_VERSION=$EV \
		      -DVERSION_BRANCH=$EV \
		      -DOUT_VERSION=$EV \
		      emacs.nsi \
	  && mv $OE $SE) \
	 | tee $TO/${EB}-esi.log \
	 && echo "5..OK executable self installer") \
	|| (echo "ERROR: creating self installer ($?)"; exit 5)

    # archive self-installer sources
    if [[ -d $IN ]] ; then
	echo "NOTICE: Found self-installer source archive, leaving: $SXS";
    else
	mv $SXS $IN ||
	    ( echo "ERROR: source restore mv failed ($?): $IN => $SXS";
	      exit 5; )
    fi
fi



# archive sources
if [[ -r $SZ ]] ; then
    echo "NOTICE: source zip exists: $SZ";
else
    # clean-up the build folder
    cd $SRC
    git clean -fxd | tee $TO/${EB}-clea.log
    # archive sources, omit git cruft
    ((zip -9r $SZ . -x .git/ .git/\* \
	  | tee $TO/${EB}-src.log
     ) && echo "6..OK archive sources"
    ) || (echo "ERROR: archive sources ($?)"; exit 4);
fi

cd $UP

# create SHA256 sums
if [[ $( ls -t *.{exe,zip,txt} 2>/dev/null | head -1 ) \
	  != \
	  $( ls *.txt 2>/dev/null ) ]] ;
then
    ((for f in *.{zip,exe} ;
      do
	  sha256sum.exe $f ;
      done) | tee $UP/${EL}-sha256sums.txt
    ) | tee $TO/${EB}-sums.log
fi

# sign release files
EXTS=exe,zip,txt
if [[ $( ls $UP/*.{$EXTS} 2>/dev/null | wc -l ) \
	  -ne \
	  $( ls $UP/*.sig 2>/dev/null | wc -l) ]] ;
then
    (for f in $UP/*.{txt,exe,zip} ;
     do
	 gpg --pinentry-mode=loopback \
	     --passphrase-file=$HOME/emacs-build/foo.txt \
	     --batch --yes -b $f
     done) | tee $TO/emacs-${SLUG}-sign.log
    exit 0
fi

# create upload directives
if [[ $( ls $UP/*.{$EXTS} 2>/dev/null | wc -l ) \
	  -ne \
	  $( ls $UP/*.directive.asc 2>/dev/null | wc -l) ]] ;
then
    (for f in *.{zip,exe,txt} ;
     do
	 cat $DIR \
	     | perl -p \
		    -e "s/__FILE__/$f/msg;" \
		    -e "s/__MAJOR_VERSION__/$MV/msg;" \
		    -e "s/__VERSION__/${EV:=$MV.0.50}/msg;" \
		    > $f.directive ;
     done) | tee $TO/emacs-${SLUG}-dirs.log

    # sign directives
    (((for f in *.directive ;
       do
	   gpg --pinentry-mode=loopback \
	       --passphrase-file=$HOME/emacs-build/foo.txt \
	       --batch --yes --clearsign $f ;
       done)  | tee $TO/emacs-${SLUG}-sidr.log
     ) && echo "7..OK prep upload"
    ) || (echo "ERROR: prep upload ($?)"; exit 4);
fi

if [[ -z "$SSH_USER" ]] || [[ -z "$SSH_KEY" ]] ;
then
    echo "Missing SSH info, skipping rsync"
else
    rsync -vvrte "/usr/bin/ssh -i $SSH_KEY" "$UP" "${SSH_USER}@corwin.bru.st:~/corwin-emacs/emacs-$MV"
    ssh -i "$SSH_KEY" "${SSH_USER}@corwin.bru.st" 'cd ~/corwin-emacs/emacs-30; ./update-sym-links.sh'
fi
