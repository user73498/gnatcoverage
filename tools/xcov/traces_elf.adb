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

with Ada.Unchecked_Conversion;
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Containers.Vectors;
with Interfaces; use Interfaces;

with Elf32;
with Elf_Disassemblers; use Elf_Disassemblers;
with Execs_Dbase;       use Execs_Dbase;
with Hex_Images;        use Hex_Images;
with Dwarf;
with Dwarf_Handling;  use Dwarf_Handling;
with System.Storage_Elements; use System.Storage_Elements;
with Traces_Sources;
with Traces_Names;
with Traces_Disa;
with Coverage; use Coverage;

with Disa_Common; use Disa_Common;

package body Traces_Elf is

   procedure Read_Word8 (Exec : Exe_File_Type;
                         Base : Address;
                         Off : in out Storage_Offset;
                         Res : out Unsigned_64);
   procedure Read_Word4 (Exec : Exe_File_Type;
                         Base : Address;
                         Off : in out Storage_Offset;
                         Res : out Unsigned_32);
   procedure Read_Word4 (Exec : Exe_File_Type;
                         Base : Address;
                         Off : in out Storage_Offset;
                         Res : out Integer_32);
   procedure Read_Word2 (Exec : Exe_File_Type;
                         Base : Address;
                         Off : in out Storage_Offset;
                         Res : out Unsigned_16);
   procedure Write_Word4 (Exec : Exe_File_Type;
                          Base : Address;
                          Off : in out Storage_Offset;
                          Val : Unsigned_32);
   procedure Write_Word4 (Exec : Exe_File_Type;
                          Base : Address;
                          Off : in out Storage_Offset;
                          Val : Integer_32);
   procedure Read_Address (Exec : Exe_File_Type;
                           Base : Address;
                           Off : in out Storage_Offset;
                           Sz : Natural;
                           Res : out Unsigned_64);
   procedure Read_Dwarf_Form_U64 (Exec : Exe_File_Type;
                                  Base : Address;
                                  Off : in out Storage_Offset;
                                  Form : Unsigned_32;
                                  Res : out Unsigned_64);
   procedure Read_Dwarf_Form_String (Exec : in out Exe_File_Type;
                                     Base : Address;
                                     Off : in out Storage_Offset;
                                     Form : Unsigned_32;
                                     Res : out Address);
   procedure Skip_Dwarf_Form (Exec : Exe_File_Type;
                              Base : Address;
                              Off : in out Storage_Offset;
                              Form : Unsigned_32);
   procedure Apply_Relocations (Exec : Exe_File_Type;
                                Sec_Rel : Elf_Half;
                                Data : in out Binary_Content);
   procedure Read_Debug_Line (Exec : in out Exe_File_Type;
                              CU_Offset : Unsigned_32);

   Empty_String_Acc : constant String_Acc := new String'("");

   ---------
   -- "<" --
   ---------

   function "<" (L, R : Addresses_Info_Acc) return Boolean is
   begin
      return L.Last < R.First;
   end "<";

   -----------
   -- Image --
   -----------

   function Image (El : Addresses_Info_Acc) return String is
      Range_Img : constant String :=
                    Hex_Image (El.First) & '-' & Hex_Image (El.Last);

      function Sloc_Image (Line, Column : Natural) return String;
      --  Return the image of the given sloc. Column info is included only
      --  if Column > 0.

      ----------------
      -- Sloc_Image --
      ----------------

      function Sloc_Image (Line, Column : Natural) return String is
         Line_Img   : constant String := Line'Img;
         Column_Img : constant String := Column'Img;
      begin
         if Column = 0 then
            return Line_Img (Line_Img'First + 1 .. Line_Img'Last);
         else
            return Line_Img (Line_Img'First + 1 .. Line_Img'Last)
              & ':'
              & Column_Img (Column_Img'First + 1 .. Column_Img'Last);
         end if;
      end Sloc_Image;

   --  Start of processing for Image

   begin
      case El.Kind is
         when Section_Addresses =>
            return Range_Img & " section " & El.Section_Name.all;

         when Compile_Unit_Addresses =>
            return Range_Img & " compile unit from "
              & El.Compile_Unit_Filename.all;

         when Subprogram_Addresses =>
            return Range_Img & " subprogram " & El.Subprogram_Name.all;

         when Symbol_Addresses =>
            return Range_Img & " symbol for " & El.Symbol_Name.all;

         when Line_Addresses =>
            return Range_Img & " line " & El.Line_Filename.all & ':'
              & Sloc_Image
                  (Line => El.Line_Number, Column => El.Column_Number);
      end case;
   end Image;

   ------------------
   -- Disp_Address --
   ------------------

   procedure Disp_Address (El : Addresses_Info_Acc) is
   begin
      Put_Line (Image (El));
   end Disp_Address;

   --------------------
   -- Disp_Addresses --
   --------------------

   procedure Disp_Addresses (Exe : Exe_File_Type; Kind : Addresses_Kind) is
      use Addresses_Containers;

      procedure Disp_Address (Cur : Cursor);
      --  Display item at Cur

      ------------------
      -- Disp_Address --
      ------------------

      procedure Disp_Address (Cur : Cursor) is
      begin
         Disp_Address (Element (Cur));
      end Disp_Address;

   --  Start of processing for Disp_Addresses

   begin
      Exe.Desc_Sets (Kind).Iterate (Disp_Address'Access);
   end Disp_Addresses;

   procedure Insert (Set : in out Addresses_Containers.Set;
                     El : Addresses_Info_Acc)
     renames Addresses_Containers.Insert;

   Bad_Stmt_List : constant Unsigned_64 := Unsigned_64'Last;

   procedure Open_File
     (Exec : out Exe_File_Type; Filename : String; Text_Start : Pc_Type)
   is
      Ehdr : Elf_Ehdr;
   begin
      Open_File (Exec.Exe_File, Filename);
      Exec.Exe_Text_Start := Text_Start;
      Ehdr := Get_Ehdr (Exec.Exe_File);
      Exec.Is_Big_Endian := Ehdr.E_Ident (EI_DATA) = ELFDATA2MSB;
      Exec.Exe_Machine := Ehdr.E_Machine;

      if Machine = 0 then
         Machine := Ehdr.E_Machine;
      elsif Machine /= Ehdr.E_Machine then
         --  Mixing different architectures.
         raise Program_Error;
      end if;

      --  Be sure the section headers are loaded.
      Load_Shdr (Exec.Exe_File);

      for I in 0 .. Get_Shdr_Num (Exec.Exe_File) - 1 loop
         declare
            Name : constant String := Get_Shdr_Name (Exec.Exe_File, I);
         begin
            if Name = ".debug_abbrev" then
               Exec.Sec_Debug_Abbrev := I;
            elsif Name = ".debug_info" then
               Exec.Sec_Debug_Info := I;
            elsif Name = ".rela.debug_info" then
               Exec.Sec_Debug_Info_Rel := I;
            elsif Name = ".debug_line" then
               Exec.Sec_Debug_Line := I;
            elsif Name = ".rela.debug_line" then
               Exec.Sec_Debug_Line_Rel := I;
            elsif Name = ".debug_str" then
               Exec.Sec_Debug_Str := I;
            end if;
         end;
      end loop;
   end Open_File;

   procedure Close_File (Exec : in out Exe_File_Type) is
   begin
      Close_File (Exec.Exe_File);

      Unchecked_Deallocation (Exec.Lines);
      Exec.Lines_Len := 0;

      Unchecked_Deallocation (Exec.Debug_Strs);
      Exec.Debug_Str_Base := Null_Address;
      Exec.Debug_Str_Len := 0;

      Exec.Sec_Debug_Abbrev   := 0;
      Exec.Sec_Debug_Info     := 0;
      Exec.Sec_Debug_Info_Rel := 0;
      Exec.Sec_Debug_Line     := 0;
      Exec.Sec_Debug_Line_Rel := 0;
      Exec.Sec_Debug_Str      := 0;
   end Close_File;

   procedure Clear_File (Exec : in out Exe_File_Type) is
   begin
      --  FIXME: free content.
      for J in Exec.Desc_Sets'Range loop
         Exec.Desc_Sets (J).Clear;
      end loop;
   end Clear_File;

   function Get_Filename (Exec : Exe_File_Type) return String is
   begin
      return Get_Filename (Exec.Exe_File);
   end Get_Filename;

   function Get_Machine (Exec : Exe_File_Type) return Unsigned_16 is
   begin
      return Exec.Exe_Machine;
   end Get_Machine;

   procedure Read_Word8 (Exec : Exe_File_Type;
                         Base : Address;
                         Off : in out Storage_Offset;
                         Res : out Unsigned_64) is
   begin
      if Exec.Is_Big_Endian then
         Read_Word8_Be (Base, Off, Res);
      else
         Read_Word8_Le (Base, Off, Res);
      end if;
   end Read_Word8;

   procedure Read_Word4 (Exec : Exe_File_Type;
                         Base : Address;
                         Off : in out Storage_Offset;
                         Res : out Unsigned_32) is
   begin
      if Exec.Is_Big_Endian then
         Read_Word4_Be (Base, Off, Res);
      else
         Read_Word4_Le (Base, Off, Res);
      end if;
   end Read_Word4;

   procedure Read_Word4 (Exec : Exe_File_Type;
                         Base : Address;
                         Off : in out Storage_Offset;
                         Res : out Integer_32)
   is
      function To_Integer_32 is new Ada.Unchecked_Conversion
        (Unsigned_32, Integer_32);
      R : Unsigned_32;
   begin
      Read_Word4 (Exec, Base, Off, R);
      Res := To_Integer_32 (R);
   end Read_Word4;

   procedure Read_Word2 (Exec : Exe_File_Type;
                         Base : Address;
                         Off : in out Storage_Offset;
                         Res : out Unsigned_16) is
   begin
      if Exec.Is_Big_Endian then
         Read_Word2_Be (Base, Off, Res);
      else
         Read_Word2_Le (Base, Off, Res);
      end if;
   end Read_Word2;

   procedure Write_Word4 (Exec : Exe_File_Type;
                          Base : Address;
                          Off : in out Storage_Offset;
                          Val : Unsigned_32) is
   begin
      if Exec.Is_Big_Endian then
         Write_Word4_Be (Base, Off, Val);
      else
         Write_Word4_Le (Base, Off, Val);
      end if;
   end Write_Word4;

   procedure Write_Word4 (Exec : Exe_File_Type;
                          Base : Address;
                          Off : in out Storage_Offset;
                          Val : Integer_32)
   is
      function To_Unsigned_32 is new Ada.Unchecked_Conversion
        (Integer_32, Unsigned_32);
      R : Unsigned_32;
   begin
      R := To_Unsigned_32 (Val);
      Write_Word4 (Exec, Base, Off, R);
   end Write_Word4;

   procedure Read_Address (Exec : Exe_File_Type;
                           Base : Address;
                           Off : in out Storage_Offset;
                           Sz : Natural;
                           Res : out Unsigned_64)
   is
   begin
      if Sz = 4 then
         declare
            V : Unsigned_32;
         begin
            Read_Word4 (Exec, Base, Off, V);
            Res := Unsigned_64 (V);
         end;
      elsif Sz = 8 then
         Read_Word8 (Exec, Base, Off, Res);
      else
         raise Program_Error;
      end if;
   end Read_Address;

   procedure Read_Dwarf_Form_U64 (Exec : Exe_File_Type;
                                  Base : Address;
                                  Off : in out Storage_Offset;
                                  Form : Unsigned_32;
                                  Res : out Unsigned_64)
   is
      use Dwarf;
   begin
      case Form is
         when DW_FORM_Addr =>
            Read_Address (Exec, Base, Off, Exec.Addr_Size, Res);
         when DW_FORM_Flag =>
            declare
               V : Unsigned_8;
            begin
               Read_Byte (Base, Off, V);
               Res := Unsigned_64 (V);
            end;
         when DW_FORM_Data1 =>
            declare
               V : Unsigned_8;
            begin
               Read_Byte (Base, Off, V);
               Res := Unsigned_64 (V);
            end;
         when DW_FORM_Data2 =>
            declare
               V : Unsigned_16;
            begin
               Read_Word2 (Exec, Base, Off, V);
               Res := Unsigned_64 (V);
            end;
         when DW_FORM_Data4
            | DW_FORM_Ref4 =>
            declare
               V : Unsigned_32;
            begin
               Read_Word4 (Exec, Base, Off, V);
               Res := Unsigned_64 (V);
            end;
         when DW_FORM_Data8 =>
            Read_Word8 (Exec, Base, Off, Res);
         when DW_FORM_Sdata =>
            declare
               V : Unsigned_32;
            begin
               Read_SLEB128 (Base, Off, V);
               Res := Unsigned_64 (V);
            end;
         when DW_FORM_Udata =>
            declare
               V : Unsigned_32;
            begin
               Read_ULEB128 (Base, Off, V);
               Res := Unsigned_64 (V);
            end;
         when DW_FORM_Strp
           | DW_FORM_String
           | DW_FORM_Block1 =>
            raise Program_Error;
         when others =>
            raise Program_Error;
      end case;
   end Read_Dwarf_Form_U64;

   procedure Read_Dwarf_Form_String (Exec : in out Exe_File_Type;
                                     Base : Address;
                                     Off : in out Storage_Offset;
                                     Form : Unsigned_32;
                                     Res : out Address)
   is
      use Dwarf;
   begin
      case Form is
         when DW_FORM_Strp =>
            declare
               V : Unsigned_32;
            begin
               Read_Word4 (Exec, Base, Off, V);
               if Exec.Debug_Str_Base = Null_Address then
                  if Exec.Sec_Debug_Str /= 0 then
                     Exec.Debug_Str_Len := Get_Section_Length
                       (Exec.Exe_File, Exec.Sec_Debug_Str);
                     Exec.Debug_Strs :=
                       new Binary_Content (0 .. Exec.Debug_Str_Len - 1);
                     Exec.Debug_Str_Base := Exec.Debug_Strs (0)'Address;
                     Load_Section (Exec.Exe_File,
                                   Exec.Sec_Debug_Str, Exec.Debug_Str_Base);
                  else
                     return;
                  end if;
               end if;
               Res := Exec.Debug_Str_Base + Storage_Offset (V);
            end;
         when DW_FORM_String =>
            Res := Base + Off;
            declare
               C : Unsigned_8;
            begin
               loop
                  Read_Byte (Base, Off, C);
                  exit when C = 0;
               end loop;
            end;
         when others =>
            Put ("???");
            raise Program_Error;
      end case;
   end Read_Dwarf_Form_String;

   procedure Skip_Dwarf_Form (Exec : Exe_File_Type;
                              Base : Address;
                              Off : in out Storage_Offset;
                              Form : Unsigned_32)
   is
      use Dwarf;
   begin
      case Form is
         when DW_FORM_Addr =>
            Off := Off + Storage_Offset (Exec.Addr_Size);
         when DW_FORM_Block1 =>
            declare
               V : Unsigned_8;
            begin
               Read_Byte (Base, Off, V);
               Off := Off + Storage_Offset (V);
            end;
         when DW_FORM_Flag
           | DW_FORM_Data1 =>
            Off := Off + 1;
         when DW_FORM_Data2 =>
            Off := Off + 2;
         when DW_FORM_Data4
           | DW_FORM_Ref4
           | DW_FORM_Strp =>
            Off := Off + 4;
         when DW_FORM_Data8 =>
            Off := Off + 8;
         when DW_FORM_Sdata =>
            declare
               V : Unsigned_32;
            begin
               Read_SLEB128 (Base, Off, V);
            end;
         when DW_FORM_Udata =>
            declare
               V : Unsigned_32;
            begin
               Read_ULEB128 (Base, Off, V);
            end;
         when DW_FORM_String =>
            declare
               C : Unsigned_8;
            begin
               loop
                  Read_Byte (Base, Off, C);
                  exit when C = 0;
               end loop;
            end;
         when others =>
            Put ("???");
            raise Program_Error;
      end case;
   end Skip_Dwarf_Form;

   procedure Apply_Relocations (Exec : Exe_File_Type;
                                Sec_Rel : Elf_Half;
                                Data : in out Binary_Content)
   is
      use Elf32;
      Relocs_Len : Elf_Size;
      Relocs : Binary_Content_Acc;
      Relocs_Base : Address;

      Shdr : Elf_Shdr_Acc;
      Off : Storage_Offset;

      R : Elf_Rela;
   begin
      Shdr := Get_Shdr (Exec.Exe_File, Sec_Rel);
      if Shdr.Sh_Type /= SHT_RELA then
         raise Program_Error;
      end if;
      if Natural (Shdr.Sh_Entsize) /= Elf_Rela_Size then
         raise Program_Error;
      end if;
      Relocs_Len := Get_Section_Length (Exec.Exe_File, Sec_Rel);
      Relocs := new Binary_Content (0 .. Relocs_Len - 1);
      Load_Section (Exec.Exe_File, Sec_Rel, Relocs (0)'Address);
      Relocs_Base := Relocs (0)'Address;

      Off := 0;
      while Off < Storage_Offset (Relocs_Len) loop
         if
           Off + Storage_Offset (Elf_Rela_Size) > Storage_Offset (Relocs_Len)
         then
            --  Truncated.
            raise Program_Error;
         end if;

         --  Read relocation entry.
         Read_Word4 (Exec, Relocs_Base, Off, R.R_Offset);
         Read_Word4 (Exec, Relocs_Base, Off, R.R_Info);
         Read_Word4 (Exec, Relocs_Base, Off, R.R_Addend);

         if R.R_Offset > Data'Last then
            raise Program_Error;
         end if;

         case Exec.Exe_Machine is
            when EM_PPC =>
               case Elf_R_Type (R.R_Info) is
                  when R_PPC_ADDR32 =>
                     null;
                  when others =>
                     raise Program_Error;
               end case;
            when others =>
               raise Program_Error;
         end case;

         Write_Word4 (Exec,
                      Data (0)'Address,
                      Storage_Offset (R.R_Offset), R.R_Addend);
      end loop;
      Unchecked_Deallocation (Relocs);
   end Apply_Relocations;

   --  Extract lang, subprogram name and stmt_list (offset in .debug_line).
   procedure Build_Debug_Compile_Units (Exec : in out Exe_File_Type)
   is
      use Dwarf;

      Abbrev_Len : Elf_Size;
      Abbrevs : Binary_Content_Acc;
      Abbrev_Base : Address;
      Map : Abbrev_Map_Acc;
      Abbrev : Address;

      Shdr : Elf_Shdr_Acc;
      Info_Len : Elf_Size;
      Infos : Binary_Content_Acc;
      Base : Address;
      Off : Storage_Offset;
      Aoff : Storage_Offset;

      Len : Unsigned_32;
      Ver : Unsigned_16;
      Abbrev_Off : Unsigned_32;
      Ptr_Sz : Unsigned_8;
      Last : Storage_Offset;
      Num : Unsigned_32;

      Tag : Unsigned_32;
      Name : Unsigned_32;
      Form : Unsigned_32;

      Level : Unsigned_8;

      At_Sib : Unsigned_64 := 0;
      At_Stmt_List : Unsigned_64 := Bad_Stmt_List;
      At_Low_Pc : Unsigned_64;
      At_High_Pc : Unsigned_64;
      At_Lang : Unsigned_64 := 0;
      At_Name : Address := Null_Address;
      Cu_Base_Pc : Unsigned_64;

      Current_Cu : Addresses_Info_Acc;
      Current_Subprg : Addresses_Info_Acc;
      Sec : Addresses_Info_Acc;
      Addr : Pc_Type;
   begin
      --  Return now if already loaded.
      if not Exec.Desc_Sets (Compile_Unit_Addresses).Is_Empty then
         return;
      end if;

      if Exec.Desc_Sets (Section_Addresses).Is_Empty then
         raise Program_Error;
      end if;

      --  Load .debug_abbrev
      Abbrev_Len := Get_Section_Length (Exec.Exe_File, Exec.Sec_Debug_Abbrev);
      Abbrevs := new Binary_Content (0 .. Abbrev_Len - 1);
      Abbrev_Base := Abbrevs (0)'Address;
      Load_Section (Exec.Exe_File, Exec.Sec_Debug_Abbrev, Abbrev_Base);

      Map := null;

      --  Load .debug_info
      Shdr := Get_Shdr (Exec.Exe_File, Exec.Sec_Debug_Info);
      Info_Len := Get_Section_Length (Exec.Exe_File, Exec.Sec_Debug_Info);
      Infos := new Binary_Content (0 .. Info_Len - 1);
      Base := Infos (0)'Address;
      Load_Section (Exec.Exe_File, Exec.Sec_Debug_Info, Base);

      if Exec.Sec_Debug_Info_Rel /= 0 then
         Apply_Relocations (Exec, Exec.Sec_Debug_Info_Rel, Infos.all);
      end if;

      Off := 0;

      while Off < Storage_Offset (Shdr.Sh_Size) loop
         --  Read .debug_info header:
         --    Length, version, offset in .debug_abbrev, pointer size.
         Read_Word4 (Exec, Base, Off, Len);
         Last := Off + Storage_Offset (Len);
         Read_Word2 (Exec, Base, Off, Ver);
         Read_Word4 (Exec, Base, Off, Abbrev_Off);
         Read_Byte (Base, Off, Ptr_Sz);
         if Ver /= 2 and Ver /= 3 then
            exit;
         end if;
         Level := 0;

         Exec.Addr_Size := Natural (Ptr_Sz);
         Cu_Base_Pc := 0;

         Build_Abbrev_Map (Abbrev_Base + Storage_Offset (Abbrev_Off), Map);

         --  Read DIEs.
         loop
            << Again >> null;
            exit when Off >= Last;
            Read_ULEB128 (Base, Off, Num);
            if Num = 0 then
               Level := Level - 1;
               goto Again;
            end if;
            if Num <= Map.all'Last then
               Abbrev := Map (Num);
            else
               Abbrev := Null_Address;
            end if;
            if Abbrev = Null_Address then
               Put ("!! abbrev #" & Hex_Image (Num) & " does not exist !!");
               New_Line;
               return;
            end if;

            --  Read tag
            Aoff := 0;
            Read_ULEB128 (Abbrev, Aoff, Tag);

            if Read_Byte (Abbrev + Aoff) /= 0 then
               Level := Level + 1;
            end if;
            --  skip child.
            Aoff := Aoff + 1;

            --  Read attributes.
            loop
               Read_ULEB128 (Abbrev, Aoff, Name);
               Read_ULEB128 (Abbrev, Aoff, Form);
               exit when Name = 0 and Form = 0;

               case Name is
                  when DW_AT_Sibling =>
                     Read_Dwarf_Form_U64 (Exec, Base, Off, Form, At_Sib);
                  when DW_AT_Name =>
                     Read_Dwarf_Form_String (Exec, Base, Off, Form, At_Name);
                  when DW_AT_Stmt_List =>
                     Read_Dwarf_Form_U64 (Exec, Base, Off, Form, At_Stmt_List);
                  when DW_AT_Low_Pc =>
                     Read_Dwarf_Form_U64 (Exec, Base, Off, Form, At_Low_Pc);
                     if Form /= DW_FORM_Addr then
                        At_Low_Pc := At_Low_Pc + Cu_Base_Pc;
                     end if;
                  when DW_AT_High_Pc =>
                     Read_Dwarf_Form_U64 (Exec, Base, Off, Form, At_High_Pc);
                     if Form /= DW_FORM_Addr then
                        At_High_Pc := At_High_Pc + Cu_Base_Pc;
                     end if;
                  when DW_AT_Language =>
                     Read_Dwarf_Form_U64 (Exec, Base, Off, Form, At_Lang);
                  when others =>
                     Skip_Dwarf_Form (Exec, Base, Off, Form);
               end case;
            end loop;

            case Tag is
               when DW_TAG_Compile_Unit =>
                  if At_Low_Pc = 0 and At_High_Pc = 0 then
                     --  This field are not required.
                     At_Low_Pc := 1;
                     At_High_Pc := 1;
                  else
                     Cu_Base_Pc := At_Low_Pc;
                  end if;

                  Addr := Exec.Exe_Text_Start + Pc_Type (At_Low_Pc);

                  --  Find section of this symbol

                  if Sec = null
                    or else (Addr not in Sec.First .. Sec.Last)
                  then
                     Sec := Get_Address_Info (Exec, Section_Addresses, Addr);
                  end if;

                  Current_Cu := new Addresses_Info'
                    (Kind                  => Compile_Unit_Addresses,
                     First                 => Addr,
                     Last                  =>
                       Exec.Exe_Text_Start + Pc_Type (At_High_Pc - 1),
                     Parent                => Sec,
                     Compile_Unit_Filename =>
                       new String'(Read_String (At_Name)),
                     Stmt_List             => Unsigned_32 (At_Stmt_List));

                  if At_High_Pc > At_Low_Pc then
                     --  Do not insert empty units

                     Exec.Desc_Sets (Compile_Unit_Addresses).
                       Insert (Current_Cu);
                  end if;

                  --  Ctxt.Lang := At_Lang;
                  At_Lang := 0;
                  At_Stmt_List := Bad_Stmt_List;

               when DW_TAG_Subprogram =>
                  if At_High_Pc > At_Low_Pc then
                     Current_Subprg :=
                       new Addresses_Info'
                       (Kind            => Subprogram_Addresses,
                        First           =>
                          Exec.Exe_Text_Start + Pc_Type (At_Low_Pc),
                        Last            =>
                          Exec.Exe_Text_Start + Pc_Type (At_High_Pc - 1),
                        Parent          => Current_Cu,
                        Subprogram_Name => new String'(Read_String (At_Name)));
                     Exec.Desc_Sets (Subprogram_Addresses).
                       Insert (Current_Subprg);
                  end if;

               when others =>
                  null;
            end case;
            At_Low_Pc := 0;
            At_High_Pc := 0;

            At_Name := Null_Address;
         end loop;
         Unchecked_Deallocation (Map);
      end loop;

      Unchecked_Deallocation (Infos);
      Unchecked_Deallocation (Abbrevs);
   end Build_Debug_Compile_Units;

   package Filenames_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive,
      Element_Type => String_Acc,
      "=" => "=");

   procedure Read_Debug_Line
     (Exec : in out Exe_File_Type; CU_Offset : Unsigned_32)
   is
      use Dwarf;
      Base : Address;
      Off : Storage_Offset;

      type Opc_Length_Type is array (Unsigned_8 range <>) of Unsigned_8;
      type Opc_Length_Acc is access Opc_Length_Type;
      Opc_Length : Opc_Length_Acc;

      procedure Unchecked_Deallocation is new Ada.Unchecked_Deallocation
        (Opc_Length_Type, Opc_Length_Acc);

      Total_Len : Unsigned_32;
      Version : Unsigned_16;
      Prolog_Len : Unsigned_32;
      Min_Insn_Len : Unsigned_8;
      Dflt_Is_Stmt : Unsigned_8;
      Line_Base : Unsigned_8;
      Line_Range : Unsigned_8;
      Opc_Base : Unsigned_8;

      B : Unsigned_8;
      Arg : Unsigned_32;

      Old_Off : Storage_Offset;
      File_Dir : Unsigned_32;
      File_Time : Unsigned_32;
      File_Len : Unsigned_32;

      Ext_Len : Unsigned_32;
      Ext_Opc : Unsigned_8;

      Last : Storage_Offset;

      Pc : Unsigned_64;
      Line, Column : Unsigned_32;
      File : Natural;
      Line_Base2 : Unsigned_32;

      Nbr_Dirnames : Unsigned_32;
      Nbr_Filenames : Unsigned_32;
      Dirnames : Filenames_Vectors.Vector;
      Filenames : Filenames_Vectors.Vector;
      Dir : String_Acc;

      procedure New_Source_Line;

      ---------------------
      -- New_Source_Line --
      ---------------------

      procedure New_Source_Line is
         use Addresses_Containers;
         Pos : Cursor;
         Inserted : Boolean;
      begin
         --  Note: Last and Parent are set by Build_Debug_Lines.
         Exec.Desc_Sets (Line_Addresses).Insert
           (new Addresses_Info'
                 (Kind => Line_Addresses,
                  First => Exec.Exe_Text_Start + Pc_Type (Pc),
                  Last => Exec.Exe_Text_Start + Pc_Type (Pc),
                  Parent => null,
                  Line_Filename => Filenames_Vectors.Element (Filenames, File),
                  Line_Number   => Natural (Line),
                  Column_Number => Natural (Column)),
                 Pos, Inserted);
         --  Ok, this may fail (if there are two lines number for the same pc).

         --  Put_Line ("pc: " & Hex_Image (Pc)
         --        & " file (" & Natural'Image (File) & "): "
         --        & Read_String (Filenames_Vectors.Element (Filenames, File))
         --        & ", line: " & Unsigned_32'Image (Line));
      end New_Source_Line;

   --  Start of processing for Read_Debug_Line

   begin
      --  Load .debug_line
      if Exec.Lines = null then
         Exec.Lines_Len := Get_Section_Length (Exec.Exe_File,
                                               Exec.Sec_Debug_Line);
         Exec.Lines := new Binary_Content (0 .. Exec.Lines_Len - 1);
         Load_Section (Exec.Exe_File,
                       Exec.Sec_Debug_Line, Exec.Lines (0)'Address);

         if Exec.Sec_Debug_Line_Rel /= 0 then
            Apply_Relocations (Exec, Exec.Sec_Debug_Line_Rel, Exec.Lines.all);
         end if;
      end if;

      Base := Exec.Lines (0)'Address;

      Off := Storage_Offset (CU_Offset);
      if Off >= Storage_Offset (Get_Section_Length (Exec.Exe_File,
                                                    Exec.Sec_Debug_Line))
      then
         return;
      end if;

      --  Read header

      Read_Word4 (Exec, Base, Off, Total_Len);
      Last := Off + Storage_Offset (Total_Len);
      Read_Word2 (Exec, Base, Off, Version);
      Read_Word4 (Exec, Base, Off, Prolog_Len);
      Read_Byte (Base, Off, Min_Insn_Len);
      Read_Byte (Base, Off, Dflt_Is_Stmt);
      Read_Byte (Base, Off, Line_Base);
      Read_Byte (Base, Off, Line_Range);
      Read_Byte (Base, Off, Opc_Base);

      Pc := 0;
      Line := 1;
      File := 1;
      Column := 0;

      Line_Base2 := Unsigned_32 (Line_Base);
      if (Line_Base and 16#80#) /= 0 then
         Line_Base2 := Line_Base2 or 16#Ff_Ff_Ff_00#;
      end if;
      Opc_Length := new Opc_Length_Type (1 .. Opc_Base - 1);
      for I in 1 .. Opc_Base - 1 loop
         Read_Byte (Base, Off, Opc_Length (I));
      end loop;

      --  Include directories

      Nbr_Dirnames := 0;
      Filenames_Vectors.Clear (Dirnames);
      loop
         B := Read_Byte (Base + Off);
         exit when B = 0;
         Filenames_Vectors.Append
           (Dirnames, new String'(Read_String (Base + Off) & '/'));
         Read_String (Base, Off);
         Nbr_Dirnames := Nbr_Dirnames + 1;
      end loop;
      Off := Off + 1;

      --  File names

      Nbr_Filenames := 0;
      Filenames_Vectors.Clear (Filenames);
      loop
         B := Read_Byte (Base + Off);
         exit when B = 0;
         Old_Off := Off;
         Read_String (Base, Off);
         Read_ULEB128 (Base, Off, File_Dir);
         if File_Dir = 0 or else File_Dir > Nbr_Dirnames then
            Dir := Empty_String_Acc;
         else
            Dir := Filenames_Vectors.Element (Dirnames, Integer (File_Dir));
         end if;
         Filenames_Vectors.Append
           (Filenames, new String'(Dir.all & Read_String (Base + Old_Off)));
         Read_ULEB128 (Base, Off, File_Time);
         Read_ULEB128 (Base, Off, File_Len);
         Nbr_Filenames := Nbr_Filenames + 1;
      end loop;
      Off := Off + 1;

      while Off < Last loop

         --  Read code

         Read_Byte (Base, Off, B);
         Old_Off := Off;

         if B < Opc_Base then
            case B is
               when 0 =>
                  Read_ULEB128 (Base, Off, Ext_Len);
                  Old_Off := Off;
                  Read_Byte (Base, Off, Ext_Opc);
                  case Ext_Opc is
                     when DW_LNE_Set_Address =>
                        Read_Address
                          (Exec, Base, Off, Elf_Arch.Elf_Addr'Size / 8, Pc);
                     when others =>
                        null;
                  end case;
                  Off := Old_Off + Storage_Offset (Ext_Len);
                  --  raise Program_Error; ???

               when others =>
                  for J in 1 .. Opc_Length (B) loop
                     Read_ULEB128 (Base, Off, Arg);
                  end loop;
            end case;

            case B is
               when DW_LNS_Copy =>
                  New_Source_Line;

               when DW_LNS_Advance_Pc =>
                  Read_ULEB128 (Base, Old_Off, Arg);
                  Pc := Pc + Unsigned_64 (Arg * Unsigned_32 (Min_Insn_Len));

               when DW_LNS_Advance_Line =>
                  Read_SLEB128 (Base, Old_Off, Arg);
                  Line := Line + Arg;

               when DW_LNS_Set_File =>
                  Read_SLEB128 (Base, Old_Off, Arg);
                  File := Natural (Arg);

               --  Why aren't these three cases covered by the "when others"
               --  clause???

               when DW_LNS_Set_Column =>
                  Read_ULEB128 (Base, Old_Off, Column);

               when
                 DW_LNS_Negate_Stmt     |
                 DW_LNS_Set_Basic_Block =>
                  null;

               when DW_LNS_Const_Add_Pc =>
                  Pc := Pc + Unsigned_64
                    (Unsigned_32 ((255 - Opc_Base) / Line_Range)
                     * Unsigned_32 (Min_Insn_Len));

               when others =>
                  null;
            end case;

         else
            B := B - Opc_Base;
            Pc := Pc + Unsigned_64 (Unsigned_32 (B / Line_Range)
                                    * Unsigned_32 (Min_Insn_Len));
            Line := Line + Line_Base2 + Unsigned_32 (B mod Line_Range);
            New_Source_Line;
         end if;
      end loop;
      Unchecked_Deallocation (Opc_Length);
   end Read_Debug_Line;

   -----------------------
   -- Build_Debug_Lines --
   -----------------------

   procedure Build_Debug_Lines (Exec : in out Exe_File_Type) is
      use Addresses_Containers;
      Cur_Cu : Cursor;
      Cur_Subprg : Cursor;
      Cur_Line, N_Cur_Line : Cursor;
      Cu : Addresses_Info_Acc;
      Subprg : Addresses_Info_Acc;
      Line : Addresses_Info_Acc;
      N_Line : Addresses_Info_Acc;

      procedure Read_CU_Lines (Cur_CU : Cursor);
      --  Read debug lines for the given compilation unit

      procedure Read_CU_Lines (Cur_CU : Cursor) is
      begin
         Read_Debug_Line (Exec, Element (Cur_CU).Stmt_List);
      end Read_CU_Lines;

   begin
      --  Return now if already loaded

      if not Exec.Desc_Sets (Line_Addresses).Is_Empty then
         return;
      end if;

      --  Be sure compile units are loaded

      Build_Debug_Compile_Units (Exec);

      --  Read all .debug_line

      Exec.Desc_Sets (Compile_Unit_Addresses).Iterate (Read_CU_Lines'Access);

      --  Set .Last and parent.

      Cur_Line := First (Exec.Desc_Sets (Line_Addresses));

      Cur_Subprg := First (Exec.Desc_Sets (Subprogram_Addresses));
      if Cur_Subprg /= No_Element then
         Subprg := Element (Cur_Subprg);
      else
         Subprg := null;
      end if;

      Cur_Cu := First (Exec.Desc_Sets (Compile_Unit_Addresses));
      if Cur_Cu /= No_Element then
         Cu := Element (Cur_Cu);
      else
         Cu := null;
      end if;

      while Cur_Line /= No_Element loop
         Line := Element (Cur_Line);
         N_Cur_Line := Next (Cur_Line);
         if N_Cur_Line /= No_Element then
            N_Line := Element (N_Cur_Line);
         else
            N_Line := null;
         end if;

         --  Be sure Subprg and Cu are correctly set

         while Subprg /= null and then Subprg.Last < Line.First loop
            Next (Cur_Subprg);
            if Cur_Subprg /= No_Element then
               Subprg := Element (Cur_Subprg);
            else
               Subprg := null;
            end if;
         end loop;

         while Cu /= null and then Cu.Last < Line.First loop
            Next (Cur_Cu);
            if Cur_Cu /= No_Element then
               Cu := Element (Cur_Cu);
            else
               Cu := null;
            end if;
         end loop;

         if N_Line /= null then

            --  Set Last

            Line.Last := N_Line.First - 1;
            if Subprg /= null then
               Line.Parent := Subprg;
            end if;
         end if;

         if Subprg /= null
           and then (Line.Last > Subprg.Last or Line.Last = Line.First)
         then
            --  Truncate current line to this subprogram

            Line.Last := Subprg.Last;
            Line.Parent := Subprg;
         end if;

         if Cu /= null
           and then (Line.Last > Cu.Last or Line.Last = Line.First)
         then
            --  Truncate current line to the CU

            Line.Last := Cu.Last;
            Line.Parent := Cu;
         end if;

         Cur_Line := N_Cur_Line;
      end loop;
   end Build_Debug_Lines;

   ---------------------
   --  Build_Sections --
   ---------------------

   procedure Build_Sections (Exec : in out Exe_File_Type) is
      Shdr : Elf_Shdr_Acc;
      Addr : Pc_Type;
      Last : Pc_Type;
   begin
      --  Return now if already built

      if not Exec.Desc_Sets (Section_Addresses).Is_Empty then
         return;
      end if;

      --  Iterate over all section headers

      for Idx in 0 .. Get_Shdr_Num (Exec.Exe_File) - 1 loop
         Shdr := Get_Shdr (Exec.Exe_File, Idx);

         --  Only A+X sections are interesting.

         if (Shdr.Sh_Flags and (SHF_ALLOC or SHF_EXECINSTR))
           = (SHF_ALLOC or SHF_EXECINSTR)
           and then (Shdr.Sh_Type = SHT_PROGBITS)
         then
            Addr := Pc_Type (Shdr.Sh_Addr + Exec.Exe_Text_Start);
            Last := Pc_Type (Shdr.Sh_Addr + Exec.Exe_Text_Start
                               + Shdr.Sh_Size - 1);

            Insert (Exec.Desc_Sets (Section_Addresses),
                    new Addresses_Info'
                    (Kind => Section_Addresses,
                     First => Addr,
                     Last => Last,
                     Parent => null,
                     Section_Name =>
                       new String'(Get_Shdr_Name (Exec.Exe_File, Idx)),
                     Section_Index => Idx,
                     Section_Content => null));
         end if;
      end loop;
   end Build_Sections;

   ----------------------------
   -- Disp_Sections_Coverage --
   ----------------------------

   procedure Disp_Sections_Coverage
     (Exec : Exe_File_Type; Base : Traces_Base)
   is
      use Addresses_Containers;
      Cur : Cursor;
      Sec : Addresses_Info_Acc;
      It : Entry_Iterator;
      Trace : Trace_Entry;
      Addr : Pc_Type;

      Cur_Subprg : Cursor;
      Subprg : Addresses_Info_Acc;

      Cur_Symbol : Cursor;
      Symbol : Addresses_Info_Acc;

      Last_Addr : Pc_Type;
      State : Trace_State;
   begin
      Cur := First (Exec.Desc_Sets (Section_Addresses));

      if not Is_Empty (Exec.Desc_Sets (Subprogram_Addresses)) then
         Cur_Subprg := First (Exec.Desc_Sets (Subprogram_Addresses));
         Subprg := Element (Cur_Subprg);
      else
         Subprg := null;
      end if;

      if not Is_Empty (Exec.Desc_Sets (Symbol_Addresses)) then
         Cur_Symbol := First (Exec.Desc_Sets (Symbol_Addresses));
         Symbol := Element (Cur_Symbol);
      else
         Symbol := null;
      end if;

      while Cur /= No_Element loop
         Sec := Element (Cur);
         Load_Section_Content (Exec, Sec);

         --  Display section name

         Put ("Section ");
         Put (Sec.Section_Name.all);
         Put (':');

         if Sec.Section_Name'Length < 16 then
            Put ((1 .. 16 - Sec.Section_Name'Length => ' '));
         end if;

         Put (' ');
         Put (Hex_Image (Sec.First));
         Put ('-');
         Put (Hex_Image (Sec.Last));
         New_Line;

         Addr := Sec.First;
         Last_Addr := Sec.Last;
         Init (Base, It, Addr);
         Get_Next_Trace (Trace, It);

         --  Search next matching symbol

         while Symbol /= null and then Addr > Symbol.First loop
            Next (Cur_Symbol);
            if Cur_Symbol = No_Element then
               Symbol := null;
               exit;
            end if;
            Symbol := Element (Cur_Symbol);
         end loop;

         --  Iterate on addresses range for this section

         while Addr <= Sec.Last loop
            Last_Addr := Sec.Last;
            State := Not_Covered;

            --  Look for the next subprogram

            while Subprg /= null and then Addr > Subprg.Last loop
               Next (Cur_Subprg);
               if Cur_Subprg = No_Element then
                  Subprg := null;
                  exit;
               end if;
               Subprg := Element (Cur_Subprg);
            end loop;

            --  Display subprogram name

            if Subprg /= null then
               if Addr = Subprg.First then
                  New_Line;
                  Put ('<');
                  Put (Subprg.Subprogram_Name.all);
                  Put ('>');
               end if;

               if Last_Addr > Subprg.Last then
                  Last_Addr := Subprg.Last;
               end if;
            end if;

            --  Display Symbol

            if Symbol /= null then
               if Addr = Symbol.First
                    and then
                  (Subprg = null or else (Subprg.Subprogram_Name.all
                                            /= Symbol.Symbol_Name.all))
               then
                  Put ('<');
                  Put (Symbol.Symbol_Name.all);
                  Put ('>');
                  if Subprg = null or else Subprg.First /= Addr then
                     Put (':');
                     New_Line;
                  end if;
               end if;

               while Symbol /= null and then Addr >= Symbol.First loop
                  Next (Cur_Symbol);
                  if Cur_Symbol = No_Element then
                     Symbol := null;
                     exit;
                  end if;
                  Symbol := Element (Cur_Symbol);
               end loop;

               if Symbol /= null and then Symbol.First < Last_Addr then
                  Last_Addr := Symbol.First - 1;
               end if;
            end if;

            if Subprg /= null and then Addr = Subprg.First then
               Put (':');
               New_Line;
            end if;

            if Trace /= Bad_Trace then
               if Addr >= Trace.First and Addr <= Trace.Last then
                  State := Trace.State;
               end if;

               if Addr < Trace.First and Last_Addr >= Trace.First then
                  Last_Addr := Trace.First - 1;

               elsif Last_Addr > Trace.Last then
                  Last_Addr := Trace.Last;
               end if;
            end if;

            Traces_Disa.For_Each_Insn
              (Sec.Section_Content (Addr .. Last_Addr),
               State, Traces_Disa.Textio_Disassemble_Cb'Access, Exec);

            Addr := Last_Addr;
            exit when Addr = Pc_Type'Last;
            Addr := Addr + 1;

            if Trace /= Bad_Trace and then Addr > Trace.Last then
               Get_Next_Trace (Trace, It);
            end if;
         end loop;

         Next (Cur);
      end loop;
   end Disp_Sections_Coverage;

   --------------------------
   -- Load_Section_Content --
   --------------------------

   procedure Load_Section_Content
     (Exec : Exe_File_Type;
      Sec  : Addresses_Info_Acc)
   is
   begin
      if Sec.Section_Content = null then
         Sec.Section_Content := new Binary_Content (Sec.First .. Sec.Last);
         Load_Section (Exec.Exe_File, Sec.Section_Index,
                       Sec.Section_Content (Sec.First)'Address);
      end if;
   end Load_Section_Content;

   ----------------------------
   -- Add_Subprograms_Traces --
   ----------------------------

   procedure Add_Subprograms_Traces
     (Exec : Exe_File_Acc; Base : Traces_Base)
   is
      use Addresses_Containers;
      use Traces_Sources;

      Cur : Cursor;
      Sym : Addresses_Info_Acc;
      Sec : Addresses_Info_Acc;

   begin
      if Is_Empty (Exec.Desc_Sets (Symbol_Addresses)) then
         return;
      end if;

      --  Iterate on symbols

      Cur := Exec.Desc_Sets (Symbol_Addresses).First;
      while Cur /= No_Element loop
         Sym := Element (Cur);

         --  Be sure the section is loaded

         Sec := Sym.Parent;
         Load_Section_Content (Exec.all, Sec);

         --  Add the code for the symbol

         begin
            Traces_Names.Add_Traces
              (Sym.Symbol_Name, Exec,
               Sec.Section_Content (Sym.First .. Sym.Last),
               Base);
         exception
            when others =>
               Disp_Address (Sym);
               raise;
         end;

         Next (Cur);
      end loop;
   end Add_Subprograms_Traces;

   ------------------------
   -- Build_Source_Lines --
   ------------------------

   procedure Build_Source_Lines
     (Exec    : Exe_File_Acc;
      Base    : Traces_Base_Acc;
      Section : Binary_Content)
   is
      use Addresses_Containers;
      use Traces_Sources;
      Cur : Cursor;
      Line : Addresses_Info_Acc;
      Prev_File : Source_File;
      Prev_Filename : String_Acc := null;

      It : Entry_Iterator;
      E : Trace_Entry;
      Pc : Pc_Type;
      No_Traces : Boolean;

      Debug : constant Boolean := False;
   begin
      Pc := Section'First;
      Init (Base.all, It, Pc);
      Get_Next_Trace (E, It);
      No_Traces := E = Bad_Trace;

      --  Skip traces that are before the section

      while E /= Bad_Trace and then E.Last < Section'First loop
         Get_Next_Trace (E, It);
      end loop;

      --  Iterate on lines

      Cur := First (Exec.Desc_Sets (Line_Addresses));
      while Cur /= No_Element loop
         Line := Element (Cur);

         --  Only add lines that are in Section

         exit when Line.Last > Section'Last;
         if Line.First >= Section'First then

            --  Get corresponding file (check previous file for speed-up)

            if Line.Line_Filename /= Prev_Filename then
               Prev_File := Find_File (Line.Line_Filename);
               Prev_Filename := Line.Line_Filename;
            end if;

            Add_Line (Prev_File, Line.Line_Number, Line, Base, Exec);

            --  Skip not-matching traces

            while not No_Traces and then E.Last < Line.First loop
               --  There is no source line for this entry

               Get_Next_Trace (E, It);
               No_Traces := E = Bad_Trace;
            end loop;

            if Debug then
               New_Line;
               Disp_Address (Line);
            end if;

            Pc := Line.First;
            loop
               --  From PC to E.First

               if No_Traces or else Pc < E.First then
                  if Debug then
                     Put_Line ("no trace for pc=" & Hex_Image (Pc));
                  end if;
                  Add_Line_State (Prev_File, Line.Line_Number, Not_Covered);
               end if;

               exit when No_Traces or else E.First > Line.Last;

               if Debug then
                  Put_Line ("merge with:");
                  Dump_Entry (E);
               end if;

               --  From E.First to min (E.Last, line.last)

               Add_Line_State (Prev_File, Line.Line_Number, E.State);

               exit when E.Last >= Line.Last;
               Pc := E.Last + 1;
               Get_Next_Trace (E, It);
               No_Traces := E = Bad_Trace;
            end loop;
         end if;

         Next (Cur);
      end loop;
   end Build_Source_Lines;

   ---------------------
   -- Set_Trace_State --
   ---------------------

   procedure Set_Trace_State
     (Base : in out Traces_Base; Section : Binary_Content)
   is
      use Addresses_Containers;

      function Coverage_State (State : Trace_State) return Trace_State;
      --  Given the branch coverage state of an instruction, return the state
      --  that corresponds to the actual coverage action xcov is performing.

      --------------------
      -- Coverage_State --
      --------------------

      function Coverage_State (State : Trace_State) return Trace_State is
      begin
         if Get_Action = Insn_Coverage then
            --  Instruction coverage; no need to trace which ways a branch
            --  has been covered.

            if State = Branch_Taken
              or else State = Both_Taken
              or else State = Fallthrough_Taken
            then
               return Covered;
            else
               return State;
            end if;

         else
            --  Branch coverage; nothing to do.
            --  In any other case (source coverage), the actual state will be
            --  computed later, based on the branch coverage results and
            --  the source coverage obligations.
            return State;
         end if;
      end Coverage_State;

      It : Entry_Iterator;
      Trace : Trace_Entry;
      Addr : Pc_Type;

   --  Start of processing for Set_Trace_State

   begin
      Addr := Section'First;
      Init (Base, It, Addr);
      Get_Next_Trace (Trace, It);

      --  Skip traces that are before the section

      while Trace /= Bad_Trace and then Trace.Last < Section'First loop
         Get_Next_Trace (Trace, It);
      end loop;

      while Trace /= Bad_Trace loop
         exit when Addr > Section'Last;
         exit when Trace.First > Section'Last;

         case Machine is
            when EM_PPC =>
               declare
                  procedure Update_Or_Split (Next_State : Trace_State);

                  Insn_Bin : Binary_Content renames Section (Trace.Last - 3
                                                          .. Trace.Last);

                  Branch     : Branch_Kind;
                  Flag_Indir : Boolean;
                  Flag_Cond  : Boolean;
                  Dest       : Pc_Type;

                  Op : constant Unsigned_8 := Trace.Op and 3;
                  Trace_Len : constant Pc_Type := Trace.Last - Trace.First + 1;

                  ---------------------
                  -- Update_Or_Split --
                  ---------------------

                  procedure Update_Or_Split (Next_State : Trace_State) is
                  begin
                     if Trace_Len > 4 then
                        Split_Trace (Base, It, Trace.Last - 4,
                                     Coverage_State (Covered));
                     end if;
                     Update_State (Base, It, Coverage_State (Next_State));
                  end Update_Or_Split;

               begin
                  --  Instructions length is 4.
                  if Trace_Len < 4 then
                     raise Program_Error;
                  end if;

                  Disa_For_Machine (Machine).Get_Insn_Properties
                    (Insn_Bin   => Insn_Bin,
                     Pc         => Insn_Bin'First, -- ???
                     Branch     => Branch,
                     Flag_Indir => Flag_Indir,
                     Flag_Cond  => Flag_Cond,
                     Dest       => Dest);

                  if Flag_Cond then
                     case Op is
                        when 0 | 1 =>
                           Update_Or_Split (Branch_Taken);
                        when 2 =>
                           Update_Or_Split (Fallthrough_Taken);
                        when 3 =>
                           Update_Or_Split (Both_Taken);
                        when others =>
                           raise Program_Error;
                     end case;

                  else
                     --  Any other case than a conditional branch:
                     --  * either a unconditional
                     --  branch (Opc = 18: b, ba, bl and bla);
                     --  * or a branch conditional with BO=1x1xx
                     --  (branch always);
                     --  * or not a branch. This last case
                     --  may happen when a trace entry has been
                     --  split; in such a case, the ???.
                     Update_State (Base, It, Coverage_State (Covered));
                  end if;
               end;

            when EM_SPARC =>
               declare
                  Op : constant Unsigned_8 := Trace.Op and 3;
                  Pc1 : Pc_Type;
                  Trace_Len : constant Pc_Type := Trace.Last - Trace.First + 1;
                  Nstate : Trace_State;

                  type Br_Kind is (Br_None,
                                   Br_Cond, Br_Cond_A,
                                   Br_Trap, Br_Call, Br_Jmpl, Br_Rett);

                  function Get_Br (Insn : Unsigned_32) return Br_Kind;
                  --  Needs comment???

                  Br1, Br2, Br : Br_Kind;

                  ------------
                  -- Get_Br --
                  ------------

                  function Get_Br (Insn : Unsigned_32) return Br_Kind is
                  begin
                     case Shift_Right (Insn, 30) is
                        when 0 =>
                           case Shift_Right (Insn, 22) and 7 is
                              when 2#010# | 2#110# | 2#111# =>
                                 if (Shift_Right (Insn, 29) and 1) = 0 then
                                    return Br_Cond;
                                 else
                                    return Br_Cond_A;
                                 end if;

                              when others =>
                                 return Br_None;
                           end case;

                        when 1 =>
                           return Br_Call;

                        when 2 =>
                           case Shift_Right (Insn, 19) and 2#111_111# is
                              when 2#111000# =>
                                 return Br_Jmpl;

                              when 2#111001# =>
                                 return Br_Rett;

                              when 2#111_010# =>
                                 return Br_Trap;

                              when others =>
                                 return Br_None;
                           end case;

                        when others =>
                           return Br_None;
                     end case;
                  end Get_Br;

               begin
                  --  Instructions length is 4

                  if Trace_Len < 4 then
                     raise Program_Error;
                  end if;

                  --  Extract last two instructions

                  if Trace_Len > 7 then
                     Br1 := Get_Br
                              (To_Big_Endian_U32 (Section (Trace.Last - 7
                                                        .. Trace.Last - 4)));
                  else
                     Br1 := Br_None;
                  end if;

                  Br2 := Get_Br
                           (To_Big_Endian_U32 (Section (Trace.Last - 3
                                                     .. Trace.Last)));

                  --  Code until the first branch is covered

                  if Br1 = Br_None then
                     Pc1 := Trace.Last - 4;
                     Br := Br2;
                  else
                     Pc1 := Trace.Last - 8;
                     Br := Br1;
                  end if;

                  if Pc1 + 1 > Trace.First then
                     Split_Trace (Base, It, Pc1, Coverage_State (Covered));
                  end if;

                  case Br is
                     when Br_Cond | Br_Cond_A =>
                        case Op is
                           when 0 => Nstate := Covered;
                           when 1 => Nstate := Branch_Taken;
                           when 2 => Nstate := Fallthrough_Taken;
                           when 3 => Nstate := Both_Taken;

                           when others =>
                              raise Program_Error;

                        end case;

                     when Br_None | Br_Call | Br_Trap | Br_Jmpl | Br_Rett =>
                        Nstate := Covered;
                  end case;

                  --  Branch instruction state

                  if Br1 = Br_None then
                     Update_State (Base, It, Coverage_State (Nstate));

                  else
                     Split_Trace (Base, It, Pc1 + 4, Coverage_State (Nstate));

                     --  FIXME: is it sure???
                     Update_State (Base, It, Coverage_State (Covered));
                  end if;
               end;

            when others =>
               exit;
         end case;

         Addr := Trace.Last;
         exit when Addr = Pc_Type'Last;
         Addr := Addr + 1;
         Get_Next_Trace (Trace, It);
      end loop;
   end Set_Trace_State;

   ---------------------
   -- Set_Trace_State --
   ---------------------

   procedure Set_Trace_State
     (Exec : Exe_File_Type; Base : in out Traces_Base)
   is
      use Addresses_Containers;
      Cur : Cursor;
      Sec : Addresses_Info_Acc;
   begin
      Cur := First (Exec.Desc_Sets (Section_Addresses));
      while Cur /= No_Element loop
         Sec := Element (Cur);

         Load_Section_Content (Exec, Sec);

         Set_Trace_State (Base, Sec.Section_Content.all);
         --  Unchecked_Deallocation (Section);

         Next (Cur);
      end loop;
   end Set_Trace_State;

   -------------------
   -- Build_Symbols --
   -------------------

   procedure Build_Symbols (Exec : Exe_File_Acc) is
      use Addresses_Containers;

      type Addr_Info_Acc_Arr is array (0 .. Get_Shdr_Num (Exec.Exe_File))
        of Addresses_Info_Acc;
      Sections_Info : Addr_Info_Acc_Arr := (others => null);
      Sec : Addresses_Info_Acc;

      Symtab_Idx : Elf_Half;
      Symtab_Shdr : Elf_Shdr_Acc;
      Symtab_Len : Elf_Size;
      Symtabs : Binary_Content_Acc;

      Strtab_Idx : Elf_Half;
      Strtab_Len : Elf_Size;
      Strtabs : Binary_Content_Acc;
      ESym : Elf_Sym;

      Sym_Type : Unsigned_8;
      Sym      : Addresses_Info_Acc;

      Cur : Cursor;
      Ok : Boolean;

   --  Start of processing for Build_Symbols

   begin
      --  Build_Sections must be called before

      if Exec.Desc_Sets (Section_Addresses).Is_Empty then
         raise Program_Error;
      end if;

      if not Exec.Desc_Sets (Symbol_Addresses).Is_Empty then
         return;
      end if;

      Cur := First (Exec.Desc_Sets (Section_Addresses));
      while Has_Element (Cur) loop
         Sec := Element (Cur);
         Sections_Info (Sec.Section_Index) := Sec;
         Next (Cur);
      end loop;

      Symtab_Idx := Get_Shdr_By_Name (Exec.Exe_File, ".symtab");
      if Symtab_Idx = SHN_UNDEF then
         return;
      end if;

      Symtab_Shdr := Get_Shdr (Exec.Exe_File, Symtab_Idx);
      if Symtab_Shdr.Sh_Type /= SHT_SYMTAB
        or else Symtab_Shdr.Sh_Link = 0
        or else Natural (Symtab_Shdr.Sh_Entsize) /= Elf_Sym_Size
      then
         return;
      end if;
      Strtab_Idx := Elf_Half (Symtab_Shdr.Sh_Link);

      Symtab_Len := Get_Section_Length (Exec.Exe_File, Symtab_Idx);
      Symtabs := new Binary_Content (0 .. Symtab_Len - 1);
      Load_Section (Exec.Exe_File, Symtab_Idx, Symtabs (0)'Address);

      Strtab_Len := Get_Section_Length (Exec.Exe_File, Strtab_Idx);
      Strtabs := new Binary_Content (0 .. Strtab_Len - 1);
      Load_Section (Exec.Exe_File, Strtab_Idx, Strtabs (0)'Address);

      for I in 1 .. Natural (Symtab_Len) / Elf_Sym_Size loop
         ESym := Get_Sym
           (Exec.Exe_File,
            Symtabs (0)'Address + Storage_Offset ((I - 1) * Elf_Sym_Size));
         Sym_Type := Elf_St_Type (ESym.St_Info);

         if  (Sym_Type = STT_FUNC or else Sym_Type = STT_NOTYPE)
           and then ESym.St_Shndx in Sections_Info'Range
           and then Sections_Info (ESym.St_Shndx) /= null
           and then ESym.St_Size > 0
         then
            Sym := new Addresses_Info'
              (Kind        => Symbol_Addresses,
               First       => Exec.Exe_Text_Start + Pc_Type (ESym.St_Value),
               Last        =>
                 Exec.Exe_Text_Start + Pc_Type (ESym.St_Value
                                                         + ESym.St_Size - 1),
               Parent      => Sections_Info (ESym.St_Shndx),
               Symbol_Name => new String'
                                (Read_String
                                   (Strtabs (ESym.St_Name)'Address)));

            Addresses_Containers.Insert
              (Exec.Desc_Sets (Symbol_Addresses), Sym, Cur, Ok);
         end if;
      end loop;

      Unchecked_Deallocation (Strtabs);
      Unchecked_Deallocation (Symtabs);
   end Build_Symbols;

   ----------------------
   -- Get_Address_Info --
   ----------------------

   function Get_Address_Info
     (Exec : Exe_File_Type;
      Kind : Addresses_Kind;
      PC   : Pc_Type) return Addresses_Info_Acc
   is
      use Addresses_Containers;
      Cur      : Cursor;

      PC_Addr  : aliased Addresses_Info (Kind);
   begin
      PC_Addr.First := PC;
      PC_Addr.Last  := PC;

      Cur := Exec.Desc_Sets (Kind).Floor (PC_Addr'Unchecked_Access);
      if Cur = No_Element or else Element (Cur).Last < PC then
         return null;
      else
         return Element (Cur);
      end if;
   end Get_Address_Info;

   ----------------
   -- Get_Symbol --
   ----------------

   function Get_Symbol
     (Exec : Exe_File_Type; Pc : Pc_Type) return Addresses_Info_Acc
   is
   begin
      return Get_Address_Info (Exec, Symbol_Addresses, Pc);
   end Get_Symbol;

   ---------------
   -- Symbolize --
   ---------------

   procedure Symbolize
     (Sym      : Exe_File_Type;
      Pc       : Traces.Pc_Type;
      Line     : in out String;
      Line_Pos : in out Natural)
   is
      procedure Add (C : Character);
      --  Add C to the line

      procedure Add (Str : String);
      --  Add STR to the line

      Symbol : constant Addresses_Info_Acc := Get_Symbol (Sym, Pc);

      ---------
      -- Add --
      ---------

      procedure Add (C : Character) is
      begin
         if Line_Pos <= Line'Last then
            Line (Line_Pos) := C;
            Line_Pos := Line_Pos + 1;
         end if;
      end Add;

      ---------
      -- Add --
      ---------

      procedure Add (Str : String) is
      begin
         for I in Str'Range loop
            Add (Str (I));
         end loop;
      end Add;

   --  Start of processing for Symbolize

   begin
      if Symbol = null then
         return;
      end if;

      Add (" <");
      Add (Symbol.Symbol_Name.all);
      if Pc /= Symbol.First then
         Add ('+');
         Add (Hex_Image (Pc - Symbol.First));
      end if;
      Add ('>');
   end Symbolize;

   -------------------
   -- Init_Iterator --
   -------------------

   procedure Init_Iterator
     (Exe  : Exe_File_Type;
      Kind : Addresses_Kind;
      It   : out Addresses_Iterator)
   is
      use Addresses_Containers;
   begin
      It.Cur := Exe.Desc_Sets (Kind).First;
   end Init_Iterator;

   -------------------
   -- Next_Iterator --
   -------------------

   procedure Next_Iterator
     (It : in out Addresses_Iterator; Addr : out Addresses_Info_Acc)
   is
      use Addresses_Containers;
   begin
      if It.Cur = No_Element then
         Addr := null;
      else
         Addr := Element (It.Cur);
         Next (It.Cur);
      end if;
   end Next_Iterator;

   ------------------------
   -- Read_Routines_Name --
   ------------------------

   procedure Read_Routines_Name (Exec : Exe_File_Acc; Exclude : Boolean) is
      use Addresses_Containers;
      use Traces_Names;

      procedure Process_Symbol (Cur_Sym : Addresses_Containers.Cursor);
      procedure Process_Symbol (Cur_Sym : Addresses_Containers.Cursor) is
         Sym : Addresses_Info_Acc renames Element (Cur_Sym);
      begin
         if not Exclude then
            Add_Routine_Name
              (Name => Sym.Symbol_Name, Exec => Exec, Sym => Sym);
         else
            Remove_Routine_Name (Sym.Symbol_Name);
         end if;
      end Process_Symbol;

   --  Start of processing for Read_Routines_Name

   begin
      Build_Sections (Exec.all);
      Build_Symbols (Exec);
      Exec.Desc_Sets (Symbol_Addresses).Iterate (Process_Symbol'Access);
   end Read_Routines_Name;

   ------------------------
   -- Read_Routines_Name --
   ------------------------

   procedure Read_Routines_Name
     (Filename  : String;
      Exclude   : Boolean;
      Keep_Open : Boolean)
   is
      Exec : Exe_File_Acc;
   begin
      Open_Exec (Get_Exec_Base, Filename, Exec);

      declare
         Efile : Elf_File renames Exec.Exe_File;
      begin
         Load_Shdr (Efile);
         Read_Routines_Name (Exec, Exclude => Exclude);
         if not Keep_Open then
            Close_File (Efile);
         end if;
      end;
   exception
      when Elf_Files.Error =>
         Put_Line (Standard_Output, "cannot open: " & Filename);
         raise;
   end Read_Routines_Name;

   ------------------------
   -- Build_Source_Lines --
   ------------------------

   procedure Build_Source_Lines is
      use Traces_Names;

      procedure Build_Source_Lines_For_Routine
        (Name : String_Acc;
         Info : in out Subprogram_Info);
      --  Build source line information from debug information for the given
      --  routine.

      procedure Build_Source_Lines_For_Routine
        (Name : String_Acc;
         Info : in out Subprogram_Info)
      is
         pragma Unreferenced (Name);
      begin
         Build_Debug_Lines (Info.Exec.all);
         Build_Source_Lines (Info.Exec, Info.Traces, Info.Insns.all);
      end Build_Source_Lines_For_Routine;
   begin
      Iterate (Build_Source_Lines_For_Routine'Access);
   end Build_Source_Lines;

   --------------------------------
   -- Build_Routines_Trace_State --
   --------------------------------

   procedure Build_Routines_Trace_State is
      use Traces_Names;

      procedure Process_One
        (Name : String_Acc;
         Info : in out Subprogram_Info);
      --  Set trace state for the given routine

      procedure Process_One
        (Name : String_Acc;
         Info : in out Subprogram_Info)
      is
         pragma Unreferenced (Name);
      begin
         if Info.Insns /= null then
            Set_Trace_State (Info.Traces.all, Info.Insns.all);
         end if;
      end Process_One;
   begin
      Iterate (Process_One'Access);
   end Build_Routines_Trace_State;

end Traces_Elf;
