with Support, Expr; use Support, Expr;

procedure Test_Expr_T is
begin
   Assert (F (True, True) = True);
end;

--# expr.adb
--  /eval/  l! ## oF-
--  /retTrue/  l+ ## 0
--  /retFalse/ l- ## s-
--  /retVal/   l+ ## 0
