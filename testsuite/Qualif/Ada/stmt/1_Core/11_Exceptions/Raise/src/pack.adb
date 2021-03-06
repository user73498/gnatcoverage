package body Pack is
   pragma Unsuppress (All_Checks);

   -----------
   -- Proc1 --
   -----------

   procedure Proc1 (I : in out My_Int) is
   begin
      if I = My_Int'Last then        -- # proc1
         raise My_Exception;         -- # raise_proc1
      end if;

      I := I + 1;                    -- # no_raise_proc1
   exception
      when others  =>
         I := 0;                     -- # raise_proc1
   end Proc1;

   ----------
   -- Fun1 --
   ---------

   function Fun1 (I : My_Int) return My_Int is
      Res : My_Int := I;             -- # fun1
   begin
      if I = My_Int'Last then        -- # fun1
         raise My_Exception;         -- # raise_fun1
      end if;

      Res := Res + 1;                -- # no_raise_fun1

      return Res;                    -- # no_raise_fun1
   exception
      when others =>
         return 0;                   -- # raise_fun1
   end Fun1;

   -----------
   -- Proc2 --
   -----------

   procedure Proc2 (I : in out My_Int) is
   begin
      if I = My_Int'Last then        -- # proc2
         raise Constraint_Error;     -- # raise_proc2
      end if;

      I := I + 1;                    -- # no_raise_proc2
   exception
      when others =>
         I := 0;                     -- # raise_proc2
   end Proc2;

   ----------
   -- Fun2 --
   ---------

   function Fun2 (I : My_Int) return My_Int is
      Res : My_Int := I;             -- # fun2
   begin
      if I = My_Int'Last then        -- # fun2
         raise Constraint_Error;     -- # raise_fun2
      end if;

      Res := Res + 1;                -- # no_raise_fun2

      return Res;                    -- # no_raise_fun2
   exception
      when Constraint_Error =>
         return 0;                   -- # raise_fun2
   end Fun2;

   -----------
   -- Proc3 --
   -----------

   procedure Proc3 (I : in out My_Int) is
   begin
      I := I + 1;                    -- # proc3
      I := I / 2;                    -- # no_raise_proc3
   exception
      when others =>
         I := 0;                     -- # raise_proc3
   end Proc3;

   ----------
   -- Fun3 --
   ---------

   function Fun3 (I : My_Int) return My_Int is
      Res : My_Int := I;             -- # fun3
   begin
      Res := Res + 1;                -- # fun3

      return Res;                    -- # no_raise_fun3
   exception
      when Constraint_Error =>
         return 0;                   -- # raise_fun3
   end Fun3;

   -----------
   -- Proc4 --
   -----------

   procedure Proc4 (I : in out My_Int) is
   begin

      begin
         if I = My_Int'First then     -- # proc4
            raise My_Exception;       -- # raise_my_exception_proc4
         end if;

         I := I - 1;                  -- # after_raise_proc4

         if I > My_Int'Last - 10 then -- # after_raise_proc4
            raise Constraint_Error;   -- # raise_constraint_error_proc4
         elsif I > 0 then             -- # elsif_proc4
               I := I + 10;           -- # in_elsif_proc4
         end if;

         I := I / 2;                  -- # after_if_proc4
      exception
         when Constraint_Error =>
            I := 1;                   -- # constraint_error_handler_proc4
      end;
   exception
      when others =>
         I := 2;                      -- # others_handler_proc4
   end Proc4;

   ----------
   -- Fun4 --
   ---------

   function Fun4 (I : My_Int) return My_Int is
      Res : My_Int := I;                -- # fun4
   begin
      begin
         if Res = My_Int'First then     -- # fun4
            raise Constraint_Error;     -- # raise_constraint_error_fun4
         end if;

         Res := Res - 1;                -- # after_raise_fun4

         if Res > My_Int'Last - 10 then -- # after_raise_fun4
            raise My_Exception;         -- # raise_my_exception_fun4
         elsif Res > 0 then             -- # elsif_fun4
            Res := Res + 10;            -- # in_elsif_fun4
         end if;

         Res := Res / 2;                -- # after_if_fun4

         return Res;                    -- # after_if_fun4
      exception
         when My_Exception =>
            return 2;                   -- # my_exception_handler_fun4
      end;
   exception
      when others =>
         return 1;                      -- # others_handler_fun4
   end Fun4;

end Pack;
