#include "dowhile.h"

int
main (void)
{
  dowhile (10, GOTO_IN);
  return 0;
}

//# dowhile.c
//  /body/      l+ ## 0
//  /goto-in/   l+ ## 0
//  /eval/      l+ ## 0
//  /while/     l+ ## 0
//  /goto-out/  l- ## s-