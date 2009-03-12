------------------------------------------------------------------------------
--                                                                          --
--                              Couverture                                  --
--                                                                          --
--                     Copyright (C) 2008-2009, AdaCore                     --
--                                                                          --
-- Couverture is free software; you can redistribute it  and/or modify it   --
-- under terms of the GNU General Public License as published by the Free   --
-- Software Foundation; either version 2, or (at your option) any later     --
-- version.  Couverture is distributed in the hope that it will be useful,  --
-- but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHAN-  --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public --
-- License  for more details. You  should  have  received a copy of the GNU --
-- General Public License  distributed with GNAT; see file COPYING. If not, --
-- write  to  the Free  Software  Foundation,  59 Temple Place - Suite 330, --
-- Boston, MA 02111-1307, USA.                                              --
--                                                                          --
------------------------------------------------------------------------------

--  Management of the routines database

with Traces_Dbase; use Traces_Dbase;
with Traces_Elf; use Traces_Elf;
with Strings; use Strings;

package Traces_Names is

   procedure Add_Routine_Name (Name : String_Acc);
   --  Add a routine name to the database, and allocate an associated
   --  Subprogram_Info record (see below). Constraint_Error is propagated if
   --  the name already exists.

   --  Information recorded about each subprogram in the routines database

   type Subprogram_Info is record
      Exec  : Exe_File_Acc;
      --  Pointer to the Exec file where this subprogram has first been
      --  found.

      Insns : Binary_Content_Acc;
      --  Subprogram binary content.

      Traces : Traces_Base_Acc;
      --  Traces for the subprogram.
   end record;

   procedure Remove_Routine_Name (Name : String_Acc);
   --  Remove a routine from the database

   procedure Iterate
     (Proc : access procedure (Subp_Name : String_Acc;
                               Subp_Info : in out Subprogram_Info));
   --  Execute Proc for each routine in the database

   procedure Read_Routines_Name_From_Text (Filename : String);
   --  Read a list of routines name from a text file in the following format:
   --  * lines starting with '#' are ignored
   --  * one name per line
   --  * no blanks allowed.

   --  Display the list of routines (on standard output).
   procedure Disp_All_Routines;

   procedure Add_Traces
     (Routine_Name : String_Acc;
      Exec         : Exe_File_Acc;
      Content      : Binary_Content;
      Base         : Traces_Base);
   --  Add a set of execution traces to the trace database associated
   --  to a routine.
   --
   --  Parameters:
   --  * Routine_Name: name of the routine to consider;
   --  * Exec: handle to the executable that generated the execution traces
   --  that we consider.
   --  * Content: slice of the binary content of Exec's .text section that
   --  corresponds to the routine to consider (Content'First being the
   --  address of the routine in Exec's .text);
   --  * Base: execution traces to merge into the routine's trace database.
   --
   --  As the execution traces shall have been generated by the execution of
   --  Exec, the traces that corresponds to the routine to consider should
   --  have their execution addresses (Last, First) in a non-empty
   --  intersection with Content'Range. Or, in order words, such an entry E
   --  should verify:
   --
   --     E.First in Content'Range or E.Last in Content'Range
   --
   --  Any trace that does not verify the condition will be dropped. At the
   --  contrary, a trace that verifies this condition will be added to the
   --  corresponding subprogram traces, provided that the routine's content
   --  in Exec is the same as the one of the corresponding subprogram in the
   --  routine database (if this condition is not met, a Consolidation_Error
   --  is raised). The trace may also be rebased and split before being added
   --  to the routine traces, to verify:
   --
   --     E.First in Subp_Info.Insns'Range and E'Last in Subp_Info'Range
   --
   --  (Subp_Info being the corresponding subprogram info in the routine
   --  database).

   Consolidation_Error : exception;
   --  Raised if consolidation is not possible (eg different code for a
   --  function).

end Traces_Names;
