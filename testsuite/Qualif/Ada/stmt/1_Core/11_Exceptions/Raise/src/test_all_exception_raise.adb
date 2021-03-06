--  Test driver for exception raise. It calls all the subprograms from the
--  functional code, but does it in such a way that each subprogram raises
--  an exception (by executing the RAISE statement or as a result of a
--  predefined run-time check). So the code that follows the raise statement
--  in effect and constructs implicitely raising predefined exceptions shall be
--  reported as uncovered.

with Pack;    use Pack;
with Support; use Support;
procedure Test_All_Exception_Raise is
   Int : My_Int := 100;
begin
   Proc1 (Int);
   Assert (Int = 0);

   Assert (Fun1 (100) = 0);

   Int := 100;
   Proc2 (Int);
   Assert (Int = 0);

   Assert (Fun2 (100) = 0);

   Int := 100;
   Proc3 (Int);
   Assert (Int = 0);

   Assert (Fun3 (100) = 0);

   Int := 100;
   Proc4 (Int);
   Assert (Int = 1);

   Assert (Fun4 (-100) = 1);

end;
--#  pack.adb
-- /proc1/                          l+ ## 0
-- /raise_proc1/                    l+ ## 0
-- /no_raise_proc1/                 l- ## s-

-- /fun1/                           l+ ## 0
-- /raise_fun1/                     l+ ## 0
-- /no_raise_fun1/                  l- ## s-

-- /proc2/                          l+ ## 0
-- /raise_proc2/                    l+ ## 0
-- /no_raise_proc2/                 l- ## s-

-- /fun2/                           l+ ## 0
-- /raise_fun2/                     l+ ## 0
-- /no_raise_fun2/                  l- ## s-

-- /proc3/                          l+ ## 0
-- /no_raise_proc3/                 l- ## s-
-- /raise_proc3/                    l+ ## 0

-- /fun3/                           l+ ## 0
-- /raise_fun3/                     l+ ## 0
-- /no_raise_fun3/                  l- ## s-

-- /proc4/                          l+ ## 0
-- /raise_my_exception_proc4/       l- ## s-
-- /after_raise_proc4/              l+ ## 0
-- /raise_constraint_error_proc4/   l+ ## 0
-- /elsif_proc4/                    l- ## s-
-- /in_elsif_proc4/                 l- ## s-
-- /after_if_proc4/                 l- ## s-
-- /constraint_error_handler_proc4/ l+ ## 0
-- /others_handler_proc4/           l- ## s-

-- /fun4/                           l+ ## 0
-- /raise_constraint_error_fun4/    l+ ## 0
-- /after_raise_fun4/               l- ## s-
-- /raise_my_exception_fun4/        l- ## s-
-- /elsif_fun4/                     l- ## s-
-- /in_elsif_fun4/                  l- ## s-
-- /after_if_fun4/                  l- ## s-
-- /my_exception_handler_fun4/      l- ## s-
-- /others_handler_fun4/            l+ ## 0
