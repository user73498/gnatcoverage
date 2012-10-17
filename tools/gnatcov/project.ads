------------------------------------------------------------------------------
--                                                                          --
--                               GNATcoverage                               --
--                                                                          --
--                        Copyright (C) 2012, AdaCore                       --
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

--  GNAT projects support

with GNAT.Strings; use GNAT.Strings;

with Inputs;

package Project is

   procedure Load_Root_Project (Prj_Name : String);
   --  Load the project tree rooted at Prj_Name (with optional
   --  Project_File_Extension).

   procedure Add_Project (Prj_Name : String);
   --  Add Prj_Name to the list of projects for which coverage analysis is
   --  desired. This must be a project in the closure of the previously loaded
   --  root project. Prj_Name may optionally have a Project_File_Extension.

   procedure Add_Scenario_Var (Key, Value : String);
   --  Set the indicated scenario variable to the given value

   procedure Compute_Project_View;
   --  Recompute the view of the loaded project within the current scenario

   procedure Set_Subdirs (Subdir : String);
   --  Set the object subdir for all loaded projects

   --------------------------------------
   -- Accessors for project properties --
   --------------------------------------

   procedure Enumerate_LIs
     (LI_Cb          : access procedure (LI_Name : String);
      Override_Units : Inputs.Inputs_Type);
   --  Call LI_Cb once for every library information (ALI/GLI) file from a
   --  project mentioned in a previous Add_Project call. If Override_Units is
   --  present, it overrides the set of units to be considered, else the set
   --  defined by the project through the Units, Units_List, Exclude_Units, and
   --  Exclude_Units_List attributes is used.

   function Switches_From_Project (Op : String) return String_List_Access;
   --  Return a list of gnatcov switches defined by the root project. Caller
   --  is responsible for deallocation.

end Project;
