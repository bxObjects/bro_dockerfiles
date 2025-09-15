#!/usr/bin/env python

####+BEGIN: b:prog:file/particulars :authors ("./inserts/authors-mb.org")
""" #+begin_org
* *[[elisp:(org-cycle)][| Particulars |]]* :: Authors, version
** This File: /bisos/git/bxRepos/bxObjects/bro_vagrantDebianBaseBoxes/qemu/debian/13/trixie/amd64/netinst/vagBox.cs
** File True Name: /bisos/git/auth/bxRepos/bxObjects/bro_vagrantDebianBaseBoxes/qemu/debian/13/trixie/amd64/netinst/vagBox.cs
** Authors: Mohsen BANAN, http://mohsen.banan.1.byname.net/contact
#+end_org """
####+END:

from bisos import b
from bisos.b import cs

from bisos.b import b_io

from bisos.basics import pathPlus
from pathlib import Path

from bisos.vagrantBaseBoxes import vagBoxSeed

def list_pkr_hcl_files():
    cwd = Path.cwd()
    return [file.name for file in cwd.iterdir() if file.is_file() and file.suffixes == ['.pkr', '.hcl']]

vagBoxSeed.setup(
    seedType="common",
    vagBoxList=list_pkr_hcl_files(),
    # examplesHook=examples_csu,
)

####+BEGIN: b:py3:cs:cmnd/classHead :cmndName "symlinksToPoly" :extent "verify" :comment "" :parsMand "" :parsOpt "" :argsMin 0 :argsMax 0 :pyInv ""
""" #+begin_org
*  _[[elisp:(blee:menu-sel:outline:popupMenu)][±]]_ _[[elisp:(blee:menu-sel:navigation:popupMenu)][Ξ]]_ [[elisp:(outline-show-branches+toggle)][|=]] [[elisp:(bx:orgm:indirectBufOther)][|>]] *[[elisp:(blee:ppmm:org-mode-toggle)][|N]]*  CmndSvc-   [[elisp:(outline-show-subtree+toggle)][||]] <<symlinksToPoly>>  =verify= ro=cli   [[elisp:(org-cycle)][| ]]
#+end_org """
class symlinksToPoly(cs.Cmnd):
    cmndParamsMandatory = [ ]
    cmndParamsOptional = [ ]
    cmndArgsLen = {'Min': 0, 'Max': 0,}

    @cs.track(fnLoc=True, fnEntry=True, fnExit=True)
    def cmnd(self,
             rtInv: cs.RtInvoker,
             cmndOutcome: b.op.Outcome,
    ) -> b.op.Outcome:

        failed = b_io.eh.badOutcome
        callParamsDict = {}
        if self.invocationValidate(rtInv, cmndOutcome, callParamsDict, None).isProblematic():
            return failed(cmndOutcome)
####+END:
        self.cmndDocStr(f""" #+begin_org
** [[elisp:(org-cycle)][| *CmndDesc:* | ]] Create symlinks to poly base dir.
        #+end_org """)

        # ln -s ../../../../../../poly/debian/12/netinst/12.11.0-netinst_us.pkr.hcl us.pkr.hcl
        polyBaseDir = "../../../../../../poly/debian/12/netinst"

        pathPlus.symlink_update(f"{polyBaseDir}/12.11.0-netinst_us.pkr.hcl", "us.pkr.hcl",)
        pathPlus.symlink_update(f"{polyBaseDir}/12.11.0-netinst_pt.pkr.hcl", "pt.pkr.hcl",)
        pathPlus.symlink_update(f"{polyBaseDir}/provision.sh", "provision.sh",)
        pathPlus.symlink_update(f"{polyBaseDir}/preseed-deb12-us.txt", "preseed-deb12-us.txt",)
        pathPlus.symlink_update(f"{polyBaseDir}/preseed-deb12-pt.txt", "preseed-deb12-pt.txt",)
        pathPlus.symlink_update(f"{polyBaseDir}/provision-guest-additions.sh", "provision-guest-additions.sh",)
        pathPlus.symlink_update(f"{polyBaseDir}/README.org", "README.org",)
        pathPlus.symlink_update(f"{polyBaseDir}/Vagrantfile-uefi.template", "Vagrantfile-uefi.template",)

        return cmndOutcome.set(
            opError=b.op.OpError.Success,
            opResults="Updated symlinks to poly",
        )

def examples_csu() -> None:
    cs.examples.menuChapter(f'*Seed Extensions*')
    cs.examples.cmndEnter('symlinksToPoly', comment=" # Updatres Symlinks to Poly")
