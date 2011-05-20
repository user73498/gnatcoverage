# ***************************************************************************
# **                             TEST SUITE CONTROL                        **
# ***************************************************************************

from gnatpython.env import Env
import os.path

env = Env()

# Append .exe on windows for native tools
GPRBUILD  = 'gprbuild' + env.host.os.exeext
GPRCONFIG = 'gprconfig' + env.host.os.exeext
GPRCLEAN  = 'gprclean' + env.host.os.exeext
XCOV      = 'xcov' + env.host.os.exeext

class LangInfo:
    """A class that provides some info about a given language.

    ATTRIBUTES:
        name:    The name of the language. Eg: "Ada", or "C".
        src_ext: A list of extensions used for filenames of that language.
                 Eg: [".ads", ".adb"] for GNAT, or [".h", ".c"] for C.
        scos_ext: The extension used for filenames that contain
                 the SCOs used by xcov. For instance, in Ada,
                 that would be ".ali".
        comment: The comment marker used by that language to specify
                 the start of a comment that runs until the end of
                 the current line.  For instance, in Ada, it would be
                 '--'.
    """
    def __init__(self, name, src_ext, scos_ext, comment):
        # The parameters have the same meaning as the class'
        # attributes, with the following exceptions:
        #     src_ext: If only one filename extension is being used,
        #         it is acceptable to pass it directly, rather than
        #         passing a single-element list.  This constructor
        #         will automatically make the translation.
        if not isinstance(src_ext, list):
            src_ext = [src_ext]
        self.name = name
        self.src_ext = src_ext
        self.scos_ext = scos_ext
        self.comment = comment

# The list of known languages...
KNOWN_LANGUAGES = (LangInfo(name="Ada", src_ext=[".ads", ".adb"],
                            scos_ext=".ali", comment='--'),
                   LangInfo(name="C", src_ext=[".h", ".c"],
                            scos_ext=".gli", comment='//'),
                   LangInfo(name="Consolidation", src_ext=".txt",
                            scos_ext=None, comment='--'))

def language_info(source_filename):
    """Return the LangInfo associated to a given source filename.
    The language is determined based on the filename extension.

    Return None if we couldn't determine the language.
    """
    ext = os.path.splitext(source_filename)[1]
    for lang_info in KNOWN_LANGUAGES:
        if ext in lang_info.src_ext:
            return lang_info
    return None

class BUILDER:

    COMMON_CARGS = " -g -fpreserve-control-flow "
    SCOV_CARGS = " -gnateS "

    BASE_COMMAND = GPRBUILD

    @staticmethod
    def CONFIG_COMMAND (toplev_options):

        # When --rtsgpr is provided (and non empty), e.g. for Ravenscar,
        # assume it controls the necessary --RTS flags to pass. Otherwise,
        # assume we are targetting zfp and configure to pass --RTS=zfp by
        # default for Ada

        defrts = "zfp" if not toplev_options.rtsgpr else ""

        return " ".join ((
                GPRCONFIG, '--batch',
                '--config=C --config=Asm --config=Ada,,%s' % defrts,
                '--target=%s' % env.target.triplet, '-o suite.cgpr'))



