#!/usr/bin/env python

import os
import rest
import glob
import re

DOC_DIR = "source"
ROOT_DIR = "../../../testsuite/Qualif/Ada"

# **********************
# ** Helper functions **
# **********************

def get_content(filename):
    """Return contents of a file"""
    fd = open(filename, 'r')
    content = fd.read()
    fd.close()
    return content

def copy(l):
    """Return a copy of list L"""
    return [item for item in l]

def to_title(str):
    """Given an entity name return a suitable string to be insterted
    in the documentation"""
    m = re.search(r'^[0-9]+_(.*)$', str)
    if m is not None:
        str = m.group(1)
    return str.replace('_', ' ')

def header(str, pre_skip, post_skip):
    """Return the string to be used as a section header for STR,
    framed with PRE_SKIP new_lines before and POST_SKIP new_lines after"""
    return '\n' * pre_skip + str + '\n' * post_skip

def sec_header(str):
    """Return a Section header text to be used for section title STR"""
    return header(rest.strong(str), pre_skip=2, post_skip=2)

def subsec_header(str):
    """Return a Subsection header text to be used for subsection title STR"""
    return header(rest.emphasis(str), pre_skip=2, post_skip=2)

def warn_if(cond, text):
    if cond: print "warning: %s" % text

# ***************************
# ** Directory abstraction **
# ***************************

# DocGenerator helper to process one specific subdirectory of the TOR/TC
# hierarchy

class Dir:
    def __init__(self, root, subdirs, files, dgen):

        # Parent DocGenerator driver and os.walk values for this directory

        self.dgen    = dgen
        self.root    = root
        self.subdirs = subdirs
        self.files   = files

        # Links to parent and children in the directory tree. These are
        # set as dir objects get mapped within a DirTree instance. We expect
        # these to be constructed in a top-down fashion, and the up link is
        # assumed to be setup before other methods are called (so we know if
        # this is a root section)

        self.pdo = None
        self.subdos = []

    def has_reqtxt(self):
        return "req.txt" in self.files

    def has_settxt(self):
        return "set.txt" in self.files

    def has_tctxt(self):
        return "tc.txt" in self.files

    def has_testpy(self):
        return "test.py" in self.files

    # Generate various document sections needed for directory SELF

    def maybe_set_section(self):
        """Generate the Set description section as needed"""

        if not self.has_settxt(): return

        self.ofd.write(get_content(os.path.join(self.root, 'set.txt')))

    def maybe_req_section(self):
        """Generate the Requirement section as needed"""

        if not self.has_reqtxt(): return

        self.ofd.write(sec_header("Requirement"));
        self.ofd.write(get_content(os.path.join(self.root, 'req.txt')))

    def maybe_tc_section(self):
        """Generate the TestCase section as needed"""

        if not self.has_tctxt() and not self.has_testpy(): return

        tco = TestCase (dir=self.root, dgen=self.dgen)

        if self.has_tctxt():
            self.ofd.write(get_content(os.path.join(self.root, 'tc.txt')))

        self.ofd.write(subsec_header("Test Data"))
        self.ofd.write(rest.list(
                [':ref:`%s`' % self.dgen.ref(d) for d in tco.fnsources]))

        self.ofd.write(subsec_header("Test Procedures"))
        self.ofd.write(rest.list(
                    [':ref:`%s`' % self.dgen.ref(d) for d in tco.drsources]))
        self.ofd.write(rest.list(
                    [':ref:`%s`' % self.dgen.ref(d) for d in tco.conspecs]))

        self.dgen.register_resources (
            tco.fnsources | tco.drsources | tco.conspecs)

    def maybe_toc_section(self):
        """Generate the Table Of Contents section as needed"""

        tocentries = [self.dgen.file2docfile(os.path.join(self.root, sd))
                      for sd in self.subdirs]

        if tocentries:
            self.ofd.write(sec_header("TOC"));
            self.ofd.write(
                rest.toctree(tocentries, depth = 1 if not self.pdo else 2))

    def gen_doc_contents (self):
        dest_filename = self.dgen.file2docfile(self.root)
        self.ofd = open(os.path.join(self.dgen.doc_dir, dest_filename), 'w')

        self.ofd.write(
            rest.section(to_title(os.path.basename(self.root))))

        self.maybe_set_section()
        self.maybe_req_section()
        self.maybe_tc_section()
        self.maybe_toc_section()

        self.ofd.close()

    def walk_botmup(self, process):
        [subdo.walk_botmup(process) for subdo in self.subdos]
        process(self)

    def walk_topdown(self, process):
        process(self)
        [subdo.walk_topdown(process) for subdo in self.subdos]

    # In-tree attributes and consistency checks, once the full set of
    # of links has been established, for a bottom-up (depth first) walk

    def botmup_compute_attributes (self):

        # Properties from presence of local files, better cached to prevent
        # repeated real file presence checks

        self.req  = self.has_reqtxt()
        self.test = self.has_testpy()
        self.tc   = self.has_tctxt()
        self.set  = self.has_settxt()

        # Compute predicates over our set of children. We expect the children
        # attributes to be available here.

        some_tcorset    = False
        some_nottcorset = False

        some_reqorset    = False
        some_notreqorset = False

        some_req     = False
        some_notreq  = False
        some_tc      = False
        some_nottc   = False

        for subdo in self.subdos:
            some_req    |= subdo.req
            some_tc     |= subdo.tc

            some_notreq    |= not subdo.req
            some_nottc     |= not subdo.tc

            some_tcorset  |= subdo.tc | subdo.tcset
            some_reqorset |= subdo.req | subdo.reqset

            some_nottcorset  |= not (subdo.tc | subdo.tcset)
            some_notreqorset |= not (subdo.req | subdo.reqset)

        all_tc = not some_nottc
        all_req = not some_notreq

        self.all_reqorset = not some_notreqorset
        self.all_tcorset  = not some_nottcorset

        self.tcset = self.set and all_tc
        self.reqset = self.set and all_req

    def check_local_consistency (self):
        """Perform checks on the files present in this subdir"""

        warn_if (not (self.req or self.tc or self.set),
            "missing description text at %s" % self.root)
        warn_if (self.req and len(self.files) > 1,
            "req.txt not alone in %s" % self.root)
        warn_if (self.set and len(self.files) > 1,
            "set.txt not alone in %s" % self.root)
        warn_if (self.tc and not self.test,
            "tc.txt without test.py in %s" % self.root)
        warn_if (not self.tc and self.test,
            "test.py without tc.txt in %s" % self.root)

        warn_if(self.files and
                not self.tc and not self.set and not self.req,
            "unexpected files in %s (%s)" % (self.root, str(self.files)))

    def check_downtree_consistency (self):
        """Perform checks on the relationships between this subdir and
        its children"""

        warn_if ((self.req or self.set) and not self.subdos,
            "missing subdirs for artifact at %s" % self.root)

        if not self.subdos: return

        # Warn on structural inconsistencies

        warn_if (self.set and not (self.all_tcorset or self.all_reqorset),
            "inconsistent subdirs for set.txt at %s" % self.root)

        warn_if (self.req and not (self.all_reqorset or self.all_tcorset),
            "inconsistent subdirs down req.txt at %s" % self.root)

        warn_if (self.req and not self.all_reqorset and not self.all_tcorset,
            "missing testcases for leaf req in %s" % self.root)

    def check_uptree_consistency (self):
        pass;

    def botmup_check_consistency (self):
        self.botmup_compute_attributes ()
        self.check_local_consistency()
        self.check_downtree_consistency()
        self.check_uptree_consistency()

# *******************************
# ** Directory Tree abstraction **
# *******************************

# Helper to manage dirname -> dirobject associations and establish
# parent/children relationships over dir objects, assuming the tree
# is walked top down.

class DirTree:
    def __init__(self):
        self.dir = {}   # dir-name -> dir-object dictionary
        self.roots = [] # set of orphan dir objects

    # Hook for the DocGenerator abstraction, which it calls while walking the
    # TOR/TC file tree top down, so parents are mapped first

    def map(self, dirname, diro):

        # map this dir first ...
        self.dir[dirname] = diro

        # and setup links with/in the parent directory, the tree is walked
        # top down, so we're supposed to have seen it already when there is
        # one

        parentname = os.path.dirname(dirname)

        if parentname not in self.dir:
            self.roots.append(diro)
        else:
            parento = self.dir[parentname]
            diro.pdo = parento
            parento.subdos.append(diro)

    # Once we're past the first doc generation pass, all the parent
    # children links are set

    def walk_topdown(self,process):
        [diro.walk_topdown(process) for diro in self.roots]

    def walk_botmup(self,process):
        [diro.walk_botmup(process) for diro in self.roots]

    # Check consistency, past doc generation for the full tree so with
    # the up and down links all setup

    def check_consistency(self):
        self.walk_botmup (Dir.botmup_check_consistency)

# **************************
# ** TestCase abstraction **
# **************************

# Helper for the Directory abstraction, to encapsulate research of driver
# and functional source file sets

class TestCase:
    def __init__(self, dir, dgen):
        self.dir  = dir
        self.dgen = dgen

        self.fnsources = None
        self.drsources = None
        self.find_sources()

    def parent_globbing(self, dir, pattern, include_start_dir=True):
        """Look for src/[pattern] files in dir and its parents directory
        up to document root directory"""
        head = os.path.relpath(dir, self.dgen.root_dir)
        tail = ''
        if not include_start_dir:
            head, tail = os.path.split(head)
        files = set([])
        while len(head) > 0:
            files |= set(
                glob.glob(
                    os.path.join(self.dgen.root_dir, head, 'src', pattern))
                )
            head, tail = os.path.split(head)
        return files

    def find_with_clauses(self, dir, sourcefile):
        content = get_content(sourcefile)
        # Remove all comments
        content = '\n'.join([k for k in content.splitlines() \
                             if not re.match('\s*--', k)])

        # Find all the with clauses
        matches = re.findall(r'(?:\n|;|^)\s*with\s*([^;]+)\s*;', content, re.S)
        matches = [k.replace(' ', '') for k in matches]
        result = []
        for m in matches:
            result += m.lower().split(',')
        result = set(result)

        # Remove support package
        result -= set(['support'])

        file_list = set([])
        for item in result:

            spec = self.parent_globbing(dir, item + '.ads', True)
            warn_if (len(spec) > 1, 'multiple specs for unit "%s"' % item)
            file_list |= spec

            body = self.parent_globbing(dir, item + '.adb', True)
            warn_if (len(body) > 1, 'multiple bodies for unit "%s"' % item)
            file_list |= body

            warn_if (len(body | spec) == 0,
                'no body or spec unit "%s" (%s)' % (item, sourcefile))

        return file_list

    def find_closure(self, dir, sourcefile):
        """Given an Ada source file find it's closure. Not that we ignore the
        support package"""

        result_set = self.find_with_clauses(dir, sourcefile)

        current_size = len(result_set)
        previous_size = 0
        while current_size > previous_size:

            previous_size = current_size
            tmp = set([])
            for item in result_set:
                tmp |= self.find_with_clauses(dir, item)

            result_set |= tmp
            current_size = len(result_set)

        return result_set

    def find_sources(self):
        """Locate the functional and driver sources of testcase SELF"""

        # Seek the test drivers first, and infer closure from there. Then
        # append consolidation specs to the set of drivers. We will typically
        # end up on common functional units from drivers, so use sets to
        # prevent dupicates.

        # Test drivers: search the local "src" subdir first, walk uptree
        # if no driver there.

        local_sources = set(
            glob.glob(os.path.join(self.dir, 'src', '*.ad[sb]')))

        self.drsources = set(
            [k for k in local_sources
             if os.path.basename(k).startswith('test_')])

        if len(self.drsources) == 0:
            data_names = set(
                [os.path.basename(k).split('.')[0] for k in local_sources])
            [self.drsources.update(
                    self.parent_globbing(self.dir, 'test_'+name+'*.ad[sb]'))
             for name in data_names]

        warn_if (len(self.drsources) == 0,
            'no driver source for testcase in %s' % self.dir)

        # Driver Closure:

        self.fnsources = set([])
        [self.fnsources.update(self.find_closure(self.dir, driver))
         for driver in self.drsources]

        warn_if (len(self.fnsources) == 0,
            'no functional source for testcase in %s' % self.dir)

        # Consolidation specs. These are always local.

        self.conspecs = set([])
        self.conspecs |= set(
            glob.glob(os.path.join(self.dir, 'src', 'cons_*.txt')))

# ************************
# ** Document Generator **
# ************************

class DocGenerator(object):

    def __init__(self, root_dir, doc_dir):
        self.root_dir = os.path.abspath(root_dir)
        self.doc_dir = os.path.abspath(doc_dir)
        self.resource_list = set([])

        # current output file descriptor, while walking the tor/tc tree
        self.ofd = None

    def register_resources(self, rset):
        self.resource_list |= rset

    def file2docfile(self, filename):
        """Return the associated filename for a given path"""
        docfile = os.path.relpath(filename, self.root_dir)
        # If we are at the root directory then return our documentation
        # entry point.
        if docfile == ".":
            return "index.rst"

        docfile = docfile.replace('/', '_').replace('\\', '_') + ".rst"
        return docfile

    def ref(self, name):
        """Transform string NAME into another string suitable to be used as
        index name"""
        result = os.path.relpath(name, self.root_dir)
        return result.replace('/', '_').replace('\\', '_').replace('.', '_')


    def generate_chapter(self, root_dir):
        """Generate documentation for chapter at ROOT_DIR"""

        for root, dirs, files in os.walk(os.path.abspath(root_dir)):

            # Ignore some subdirectories
            [dirs.remove(d) for d in copy(dirs)
	     if d in ('.svn', 'src') or d.startswith('tmp_')]

            diro = Dir (root=root, subdirs=dirs, files=files, dgen=self)
            self.dirtree.map (dirname=root, diro=diro)

            diro.gen_doc_contents()

    def generate_doc(self, chapdirs):
        [self.generate_chapter(os.path.join(self.root_dir, d))
         for d in chapdirs]

    def generate_index(self, chapdirs):
        fd = open(os.path.join(self.doc_dir, 'index.rst'), 'w')
        fd.write(rest.chapter('Couverture Requirements and TestCases'))

        chapfiles = [self.file2docfile(os.path.join(self.root_dir, d))
                     for d in chapdirs]
        fd.write(rest.toctree(chapfiles, 2))
        fd.close()

    def generate_resources(self):
        fd = open(os.path.join(self.doc_dir, 'resources.rst'), 'w')
        fd.write(rest.chapter('Resources'))
        fd.write(rest.toctree(
                [self.file2docfile(d) for d in self.resource_list]))
        fd.close()

        for r in self.resource_list:
            fd = open(os.path.join(self.doc_dir, self.file2docfile(r)), 'w')
            fd.write('\n.. _%s:\n\n' % self.ref(r))
            fd.write(rest.section(os.path.basename(r)))
            fd.write(rest.code_block(get_content(r), 'ada'))
            fd.close()

    def generate_all(self):

        self.dirtree = DirTree()

        chapdirs = ['decision', 'mcdc']
        self.generate_doc(chapdirs)
        self.generate_index(chapdirs)
        self.generate_resources()

# The main of the script
if __name__ == "__main__":
    mygen = DocGenerator(ROOT_DIR, DOC_DIR)
    mygen.generate_all()
    mygen.dirtree.check_consistency()
