------------------------------------------------------------------------------
--                                                                          --
--                               GNATcoverage                               --
--                                                                          --
--                     Copyright (C) 2008-2017, AdaCore                     --
--                                                                          --
-- GNATcoverage is free software; you can redistribute it and/or modify it  --
-- under terms of the GNU General Public License as published by the  Free  --
-- Software  Foundation;  either version 3,  or (at your option) any later  --
-- version. This software is distributed in the hope that it will be useful --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public --
-- License for  more details.  You should have  received  a copy of the GNU --
-- General  Public  License  distributed  with  this  software;   see  file --
-- COPYING3.  If not, go to http://www.gnu.org/licenses for a complete copy --
-- of the license.                                                          --
------------------------------------------------------------------------------

with Interfaces; use Interfaces;
with Swaps;

package Qemu_Traces is

   --  Execution of a program with 'gnatcov run' produces an "Execution Trace"
   --  file, possibly controlled by an internal "Trace Control" file for the
   --  simulation engine to help the support of mcdc like coverage criteria.

   --  The Trace Control simulation input contains a list of addresses ranges
   --  for which branch history is needed. This is computed by xcov from SCO
   --  decision entries, and is referred to as a Decision Map.

   --  The Execution Trace output contains a list of execution trace entries
   --  generated by the simulation engine, preceded by a list of trace
   --  information entries produced by gnatcov for items such as the path to
   --  the binary file or a user provided tag string.

   --  Here is a quick sketch of the information flow:

   --                           gnatcov run                Execution Trace
   --                               |                            |
   --                               v                            v
   --                 o--------------------------------o   --------------
   --                 |    gen info section -----------|-->|Info section|
   --                 |    (date, exe file,...)        |   |------------|
   --                 |                         QEMU --|-->|Exec section|
   --  SCO decision --|--> gen decision map -----^     |   --------------
   --  entries,       |    -----------------           |
   --  for mcdc       |    |Control section|           |
   --                 |    -----------------           |
   --                 o--------------------------------o

   --  All the files sections feature a section header followed by a sequence
   --  of entries. The section header structure is identical in all cases, and
   --  always conveys some trace related data (trace control, trace context
   --  info, or actual execution trace), identified by a Kind field.

   --  The decision map file general structure is then:

   --      -------
   --      |SH   |    Section Header .Kind = Decision_Map
   --      |TCE[]|    Sequence of Trace Control Entries
   --      -------

   --  And that of the output execution tracefile is:

   --      -------
   --      |SH   |    Section Header .Kind = Info
   --      |TIE[]|    Sequence of Trace Info Entries
   --      |-----|
   --      |SH   |    Section Header .Kind = Flat|History
   --      |ETE[]|    Sequence of Exec Trace Entries
   --      -------

   -------------------------
   -- File Section Header --
   -------------------------

   --  Must be kept consistent with the C version in qemu-traces.h

   subtype Magic_String is String (1 .. 12);

   Qemu_Trace_Magic : constant Magic_String := "#QEMU-Traces";
   --  Expected value of the Magic field.

   Qemu_Trace_Version : constant Unsigned_8 := 1;
   --  Current version

   type Trace_Kind is (Flat, History, Info, Decision_Map);
   for Trace_Kind use
     (Flat         => 0,   --  flat exec trace (qemu)
      History      => 1,   --  exec trace with history (qemu)
      Info         => 2,   --  info section (gnatcov)
      Decision_Map => 3);  --  history control section (gnatcov, internal)
   for Trace_Kind'Size use 8;

   type Trace_Header is record
      Magic   : Magic_String; --  Magic string
      Version : Unsigned_8;   --  Version of file format
      Kind    : Trace_Kind;   --  Section kind

      Sizeof_Target_Pc : Unsigned_8;
      --  Size of Program Counter on target, in bytes

      Big_Endian : Boolean;
      --  True if the host is big endian

      Machine_Hi : Unsigned_8;
      Machine_Lo : Unsigned_8;
      --  Target ELF machine ID

      Padding : Unsigned_16;
      --  Reserved, must be set to 0
   end record;

   ----------------------------------------------
   -- Trace Information Section (.Kind = Info) --
   ----------------------------------------------

   --  The section header fields after Kind (but big_endian) should be 0.

   --  The section contents is a sequence of Trace Info Entries, each with a
   --  Trace Info Header followed by data. We expect an Info_End kind of entry
   --  to finish the sequence. Data interpretation depends on the entry Kind
   --  found in the item header. Note that trace info entries may also appear
   --  in the middle of trace entries, for instance to describe shared objects
   --  loading/unloading: data interpretation is also different there.

   --  Info_Kind_Type identifies the various information items that can be
   --  stored in a trace file. This section is private to gnatcov. Note that
   --  'Pos values are stored in the trace file, so the ordering of the
   --  literals must be preserved (and any new value must be added at the
   --  end), or all existing traces will become invalid.

   type Info_Kind_Type is
     (Info_End,
      --  Special entry: indicates the end of a sequence of trace info entries

      Exec_File_Name,
      --  In trace information section, this is the file name for the
      --  executable run when creating this trace. For shared objects
      --  loading/unloading, this is the shared object file name.

      Coverage_Options,
      --  ??? Unused at the time of writing

      User_Data,
      --  Arbitrary storage for user data. This is exposed to users as the
      --  trace "tag".

      Date_Time,
      --  Memory dump for the Trace_Info_Date record below. Indicates the trace
      --  file creation time.

      Kernel_File_Name,
      --  File name for the kernel used to produce this trace (if any)

      Exec_File_Size,
      --  ASCII representation of executable file size (in bytes)

      Exec_File_Time_Stamp,
      --  Human-readable date/time for the executable file modification time

      Exec_File_CRC32,
      --  ASCII representation of CRC32 checksum for the executable file, as a
      --  32-bit unsigned number.

      Coverage_Context,
      --  Streams-encoded coverage assessment context information (only set
      --  in checkpointed infos).

      Exec_Code_Size
      --  ASCII representation of the size (in bytes) of the code section
      --  (i.e. the one that contains executable instructions). In trace
      --  information section, this is the code section of the executable. For
      --  shared objects loading/unloading, this is the code section of the
      --  shared object.
     );

   type Trace_Info_Header is record
      Info_Kind   : Unsigned_32;
      --  Info_Kind_Type'Pos, in endianness indicated by file header

      Info_Length : Unsigned_32;
      --  Length of associated real data. This must be 0 for Info_End
   end record;

   --  The amount of space actually occupied in the file for each entry is
   --  always rounded up for alignment purposes. This is NOT reflected in
   --  the Info_Length header field.

   Trace_Info_Alignment : constant := 4;

   --  This is the structure of a Date_Time kind of entry:

   type Trace_Info_Date is record
      Year  : Unsigned_16;
      Month : Unsigned_8;   --  1 .. 12
      Day   : Unsigned_8;   --  1 .. 31
      Hour  : Unsigned_8;   --  0 .. 23
      Min   : Unsigned_8;   --  0 .. 59
      Sec   : Unsigned_8;   --  0 .. 59
      Pad   : Unsigned_8;   --  0
   end record;

   ---------------------------------------------------
   -- Execution Trace Section (.Kind = Raw|History) --
   ---------------------------------------------------

   --  The section contents is a sequence of Trace Entries. There is no
   --  explicit sequence termination entry ; we expect the section to end with
   --  the container file.

   --  Each trace entry conveys OPerational data about a range of machine
   --  addresses, most often execution of a basic block terminated by a branch
   --  instruction. These have slightly different representations for 32 and
   --  64 bits targets.

   --  Flat sections are meant to convey the directions taken by branches as
   --  observed locally, independently of their execution context.  This
   --  limits the output to at most two entries per block (one per possible
   --  branch outcome) and doesn't allow mcdc computation.

   --  History sections are meant to allow mcdc computation, so report block
   --  executions and branch outcomes in the relevant cases, as directed by
   --  the simulator decision map input.

   type Trace_Entry32 is record
      Pc   : Unsigned_32;
      Size : Unsigned_16;
      Op   : Unsigned_8;

      --  Padding is here only to make the size of a Trace_Entry a multiple of
      --  4 bytes, for efficiency purposes.
      Pad0 : Unsigned_8 := 0;
   end record;

   type Trace_Entry64 is record
      Pc   : Unsigned_64;
      Size : Unsigned_16;
      Op   : Unsigned_8;

      --  Padding is here only to make the size of a Trace_Entry a multiple of
      --  8 bytes, for efficiency purposes.
      Pad0 : Unsigned_8  := 0;
      Pad1 : Unsigned_32 := 0;
   end record;

   procedure Swap_Pc (V : in out Unsigned_32) renames Swaps.Swap_32;
   procedure Swap_Pc (V : in out Unsigned_64) renames Swaps.Swap_64;

   --  Size is the size of the trace (all the instructions) in bytes.

   --  The Operation conveyed is a bitmask of the following possibilities:

   Trace_Op_Block : constant Unsigned_8 := 16#10#;
   --  Basic block PC .. PC+SIZE-1 was executed. This is the usual trace when
   --  a new basic block has been executed (or when the trace generator has
   --  no memory of executed basic blocks). If this flags doesn't appear (and
   --  in that case Br0 or Br1 is usually set), the trace entry means that a
   --  new outcome (of a branch) has been executed for a basic block at PC.

   Trace_Op_Fault : constant Unsigned_8 := 16#20#;
   --  Machine fault occurred at PC. The basic block hasn't been completly
   --  executed.

   Trace_Op_Br0 : constant Unsigned_8 := 16#01#; --  Branch
   Trace_Op_Br1 : constant Unsigned_8 := 16#02#; --  Fallthrough
   --  Op_Block execution terminated with branch taken in direction 0 or 1

   Trace_Op_Special : constant Unsigned_8 := 16#80#;
   --  Special entry, emitted by the program.

   --  Special operations (in the size field of a trace):

   Trace_Special_Loadaddr : constant Unsigned_16 := 1;
   --  Module loaded at PC

   --  The following two operations are used to handle shared objects.
   --
   --  A particularity with shared objects is that their executable code can be
   --  loaded and unloaded at multiple places at different times, so there is
   --  no direct mapping: instruction <-> PC. Actually, if a program loads A,
   --  then unloads it and then loads B, executable code for A and B may share
   --  the same address space.
   --
   --  In order to precisely describe execution traces for these, we introduce
   --  two special operations to represent the shared object loading/unloading:
   --    * The load operation provides the address at which the executable
   --      code is relocated and additional informtation such as the path for
   --      the shared object file.
   --    * The unload operation just provides the address for the shared object
   --      to unload.
   --
   --  The trace entries between the load/unload couple of operations can then
   --  reference instructions from the shared object.

   Trace_Special_Load_Shared_Object   : constant Unsigned_16 := 2;
   --  This trace entry describes the event: a shared object has been loaded,
   --  its executable code has be relocated at the address indicated by this
   --  trace entry. This trace entry is followed by a sequence of Trace Info
   --  Entries. The following kind of entries are required:
   --
   --    * Exec_File_Name: the file name for the loaded shared object.
   --    * Exec_File_Size: its file size (in bytes).
   --    * Exec_Time_Stamp: its modification time.
   --    * Exec_File_CRC32: its CRC32 checksum.
   --    * Exec_Code_Size: the size (in bytes) of the code section

   Trace_Special_Unload_Shared_Object : constant Unsigned_16 := 3;
   --  This trace entry (whose address is PC) describes the event: the shared
   --  object that was previously loaded at PC has been unloaded. In order to
   --  be valid, it must exclusively match an earlier
   --  Trace_Special_Load_Shared_Object event at the same address.

   -------------------------------------------
   -- Decision Map or Trace Control Section --
   -------------------------------------------

   --  The section contents is a sequence of Trace Control Entries.

   --  Entries are meant to convey range of addresses where branch history is
   --  needed for MC/DC computation purposes. The structure is piggybacked on
   --  that of the Execution Trace output section, which has everything to
   --  represent address ranges already.

end Qemu_Traces;
