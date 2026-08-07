#!/bin/bash

####+BEGIN: bx:bsip:bash:seed-spec :types "seedFtoCommon.sh"
SEED="
*  /[dblock]/ /Seed/ :: [[file:/bisos/core/bsip/bin/seedFtoCommon.sh]] |
"
FILE="
*  /This File/ :: /bisos/git/bxRepos/bxObjects/bro_dockerfiles/debian/12/novnc/xfce/bisos:NoVncDeb12/_nodeBase_/ftoProc.sh
"
if [ "${loadFiles}" == "" ] ; then
    /bisos/core/bsip/bin/seedFtoCommon.sh -l $0 "$@"
    exit $?
fi
####+END:

seedExamplesType="pypi"

leavesExcludes=""

leavesOrdered=""

nodesExcludes=""

nodesOrdered=""

####+BEGIN: bx:dblock:pypi:bash:leavesList :types ""
leavesList="
"
####+END:

####+BEGIN: bx:dblock:pypi:bash:nodesList :types ""
nodesList="
"
####+END:

####+BEGIN: bx:dblock:bash:end-of-file :types ""
_CommentBegin_
*  [[elisp:(org-cycle)][| ]]  Common        ::  /[dblock] -- End-Of-File Controls/ [[elisp:(org-cycle)][| ]]
_CommentEnd_
#+STARTUP: showall
#local variables:
#major-mode: sh-mode
#fill-column: 90
# end:
####+END:
