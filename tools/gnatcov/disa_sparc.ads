------------------------------------------------------------------------------
--                                                                          --
--                               GNATcoverage                               --
--                                                                          --
--                     Copyright (C) 2008-2012, AdaCore                     --
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

--  SPARC disassembler

with Binary_Files;   use Binary_Files;
with Disa_Symbolize; use Disa_Symbolize;
with Disassemblers;  use Disassemblers;
with Highlighting;
with Traces;         use Traces;
with Traces_Elf;     use Traces_Elf;

package Disa_Sparc is

   type SPARC_Disassembler is new Disassembler with private;

   overriding function Get_Insn_Length
     (Self     : SPARC_Disassembler;
      Insn_Bin : Binary_Content) return Positive;
   --  Return the length of the instruction at the beginning of Insn_Bin

   overriding procedure Disassemble_Insn
     (Self     : SPARC_Disassembler;
      Insn_Bin : Binary_Content;
      Pc       : Pc_Type;
      Buffer   : in out Highlighting.Buffer_Type;
      Insn_Len : out Natural;
      Sym      : Symbolizer'Class);
   --  Disassemble instruction at ADDR, and put the result in LINE/LINE_POS.
   --  LINE_POS is the index of the next character to be written (ie line
   --  length if Line'First = 1).

   overriding procedure Get_Insn_Properties
     (Self        : SPARC_Disassembler;
      Insn_Bin    : Binary_Content;
      Pc          : Pc_Type;
      Branch      : out Branch_Kind;
      Flag_Indir  : out Boolean;
      Flag_Cond   : out Boolean;
      Branch_Dest : out Dest;
      FT_Dest     : out Dest);
   --  Determine whether the given instruction, located at PC, is a branch
   --  instruction of some kind (indicated by Branch).
   --  For a branch, indicate whether it is indirect (Flag_Indir) and whether
   --  it is conditional (Flag_Cond), and determine its destination (Dest).
   --  NOT IMPLEMENTED for SPARC (will raise Program_Error).

private
   type SPARC_Disassembler is new Disassembler with null record;
end Disa_Sparc;
