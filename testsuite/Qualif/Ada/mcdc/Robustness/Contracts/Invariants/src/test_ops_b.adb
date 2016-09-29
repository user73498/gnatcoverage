with Support, Ops;  use Support, Ops;

procedure Test_Ops_B is
   D : T_Double;
begin
   Set (D, X => 3, Y => 6);
   Assert (not Bad_Set (D));
   Set (D, X => 3, Y => 3);
   Assert (Bad_Set (D));
end;

--# ops.ads

--# ops.adb
--  /stmt/ l+ ## 0
--  /check/ l- ## s-
--  /eval/ l! ## c!:"D.Is_Set"
