**Exercise SC on local instantiations of generic units**

Check that, for a local instantiation, the code of the generic unit is
not reported as covered if the instantiation is not executed or elaborated.
Check that if a generic unit is not instantiated then its code is not reported
as covered. This test case does not check that the code of generic unit is
reported as uncovered if the unit is not instantiated or if the instantiation
is not executed/elaborated, because for unused generics in some cases no
coverage information is generated.

LRMREF: 12.3
