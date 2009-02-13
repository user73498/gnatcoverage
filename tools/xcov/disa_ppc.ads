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

with System;
with Interfaces;
with Traces;         use Traces;
with Disa_Symbolize; use Disa_Symbolize;

package Disa_Ppc is

   function Get_Insn_Length (Addr : System.Address) return Positive;
   pragma Inline (Get_Insn_Length);
   --  Return the length of the instruction at Addr

   procedure Disassemble_Insn
     (Addr     : System.Address;
      Pc       : Pc_Type;
      Line     : out String;
      Line_Pos : out Natural;
      Insn_Len : out Natural;
      Sym      : Symbolizer'Class);
   --  Disassemble instruction at ADDR, and put the result in LINE/LINE_POS.
   --  LINE_POS is the index of the next character to be written (ie line
   --  length if Line'First = 1).

   procedure Get_Insn_Properties
     (Insn       : Interfaces.Unsigned_32;
      Pc         : Pc_Type;
      Branch     : out Branch_Kind;
      Flag_Indir : out Boolean;
      Flag_Cond  : out Boolean;
      Dest       : out Pc_Type);
   --  Comment needed???

end Disa_Ppc;
