with Support, Value; use Support, Value;

procedure Test_Value_TF is
begin
   Assert (F (False) = False);
   Assert (F (True) = True);
end;

--# value.adb
-- /eval/    l+ ## 0
-- /returnTrue/  l+ ## 0
-- /returnFalse/ l+ ## 0
-- /returnVal/   l+ ## 0
