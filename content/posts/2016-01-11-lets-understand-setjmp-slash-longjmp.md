---
layout: post
title: "Let's understand: setjmp()/longjmp()"
date: 2016-02-09
comments: true
categories: assembly linux
published: true
---

Pretty recently I learned about `setjmp()` and `longjmp()`. They're a
neat pair of libc functions which allow you to save your program's current
execution context and resume it at an arbitrary point in the future (with
some caveats[^1]).
If you're wondering why this is particularly useful, to quote
the [manpage](http://linux.die.net/man/3/setjmp), one of their main use cases
is "...for dealing with errors and
interrupts encountered in a low-level subroutine of a program." These functions
can be used for more sophisticated error handling than simple error
code return values.

I was curious
how these functions worked, so I decided to take a look
at [musl libc's](http://git.musl-libc.org/cgit/musl/tree/src/setjmp/i386)
implementation for x86.
First, I'll explain their interfaces and show an example usage program.
Next, since this post isn't aimed at the assembly wizard, I'll cover some
basics of x86 and Linux calling convention to provide some required background
knowledge.
Lastly, I'll walk through the source, line by line.

## Interfaces

```c
int setjmp(jmp_buf env);
```

`setjmp()` takes a single `jmp_buf` opaque type, returns 0, and continues
execution afterward normally. A `jmp_buf` is the
structure that `setjmp()` will save the calling execution context in. We'll
examine it more closely later on.

```c
void longjmp(jmp_buf env, int val);
```

`longjmp()` takes a `jmp_buf` and an `int`, simply returning back the given
`int` value (unless it was 0, in which case it returns 1). The unusual aspect
is that when it returns, the program's execution resumes as if `setjmp()` had
just been called. This allows the user to jump back an arbitrary amount of
frames on the current call stack (presumably out of some deep routine which had
an error). The return value allows the code following the `setjmp()` call to
differentiate if `setjmp()` or `longjmp()` had just been called, and proceed
accordingly.

Here's a simple example.

```c
#include <setjmp.h>
#include <stdio.h>

void fancy_func(jmp_buf env);

int main() {
    jmp_buf env;
    int ret = setjmp(env);
    if (ret == 0) {
        puts("just returning from setjmp!");
        fancy_func(env);
    } else {
        puts("now returning from longjmp and exiting!");
    }

}

void fancy_func(jmp_buf env) {
    puts("doing fancy stuff");
    longjmp(env, 1);
}
```

Output:

```
$ ./main
just returning from setjmp!
doing fancy stuff
now returning from longjmp and exiting!
```

The above code creates a `jmp_buf` and calls `setjmp()`, saving the current
execution context. Since `setjmp()` returns 0, the code follows the
first branch, calling  `fancy_func()` and
forwarding on the `jmp_buf`. `fancy_func()` does some fancy stuff, then calls
`longjmp()`, passing in the `jmp_buf` and 1. Execution returns to the if
statement on line 9, except this time, `ret` is 1 instead of 0, because
we're returning from `longjmp()`.  Now the code
follows the `else` path which prints and exits. [^2]

## Background Knowledge

I've mentioned "execution context" a few times, but let's make that a little
more concrete. In this case, a program's execution context can be defined by
the state of the processor's registers.

On x86, the relevant registers are the general purpose, index, and pointer
registers.

```
General Purpose: eax, ebx, ecx, edx
Index:           esi, edi
Pointer:         ebp, esp, eip
```

ebx, ecx, edx, esi, and edi don't have particularly special meaning here and
can be thought of as arbitrary 32 bit storage locations. However eax, ebp, and eip
are a little different.

- eax is used for function return values (specified by the
  [cdecl](https://en.wikipedia.org/wiki/X86_calling_conventions#cdecl) calling
  convention)
- ebp, the frame pointer, contains a pointer to the start of the current stack
  frame.
- eip, the instruction pointer, contains a pointer to the next instruction to
  execute.

With this in mind, I initially thought that a `jmp_buf` would be an array
of 9 ints or something, in order to hold each register.

As it happens, `jmp_buf` is instead declared as ([link](http://git.musl-libc.org/cgit/musl/tree/include/setjmp.h#n12)):

```c
typedef struct __jmp_buf_tag {
    __jmp_buf __jb;
    unsigned long __fl;
    unsigned long __ss[128/sizeof(long)];
} jmp_buf[1];
```

And for x86, `__jmp_buf` is declared as ([link](http://git.musl-libc.org/cgit/musl/tree/arch/i386/bits/setjmp.h#n1)):

```c
typedef unsigned long __jmp_buf[6];
```

I had never seen this syntax of using bracket operators at the end of a typedef
but searched and found out that the `__jmp_buf` declaration
declares a fixed size array of 6 unsigned longs, and the `jmp_buf` declaration
declares an array of 1 `struct __jmp_buf_tag`. The reason for the array of 1
is so the pointer semantics of arrays kick in and the `struct __jmp_buf_tag`
is actually passed by reference in calls to `setjmp()`/`longjmp()` (as opposed
to being copied).

Anyway, apparently my guess of 9 ints was incorrect, and it's actually 6 (longs).

Before we
can dig into the source to understand why this is,
we need to understand what the state of
the program stack is at the point `setjmp()` is called, and to do that, we need
to understand
which calling convention is being used. Since we assume x86 Linux, this will
be [cdecl](https://en.wikipedia.org/wiki/X86_calling_conventions#cdecl). The
relevant parts of cdecl for this case are:

- arguments passed on the stack
- integer values and memory addresses returned in eax (as mentioned above)
- eax, ecx, edx are caller saved, the rest are callee saved

`setjmp()`'s code executes immediately
after `setjmp()`'s `call` instruction, so at the point the first
instruction of `setjmp()` executes, the stack looks something like this.

```
> high memory <
| ...                       |
| caller's caller saved eip |
| caller's caller saved ebp | < ebp
| caller stack var 1        | // caller's stack frame
| caller stack var 2        |
| caller stack var ...      |
| caller stack var n        |
| pointer to jmp_buf        | // argument to setjmp
| caller saved eip          | < esp
+---------------------------+ // setjmp's stack frame
> low memory <
```

(In this illustration, the stack grows down.)

At the top of the stack is the eip value that the `call` instruction pushed,
or where to return to after `setjmp()` finishes. Above that is the first,
and only argument, the pointer to the given `jmp_buf`. Lastly, above that is
the caller's stack frame.
esp points to the top 
of the stack as usual, and ebp is still pointing to the start of the caller's
stack
frame. Usually the first thing a function does is push
ebp on the stack, and set ebp to esp to now point to the current stack frame (a.k.a the prologue),
but since `setjmp()` is such a minimal function, it doesn't do this.
Furthermore, since ebp is one of the registers that needs to be saved, `setjmp()`
needs it to be unperturbed.

After `setjmp()` returns, the stack will look something like this:

```
> high memory <
| ...                       |
| caller's caller saved eip |
| caller's caller saved ebp | < ebp
| caller stack var 1        | // caller's stack frame
| caller stack var 2        |
| caller stack var ...      |
| caller stack var n        |
| pointer to jmp_buf        | < esp
+---------------------------+
> low memory <
```

It's nearly identical, except eip has been popped off the stack, and is now
executing the next instruction after the caller's `call setjmp`. esp has
also been updated accordingly. This is the state of the program that `setjmp()`
will need to record, and that `longjmp()` will restore.

Before reading the source I tried to reason about what I expected would happen.
I presume:

- General purpose and index registers (eax, ebx, ecx, edx, esi, edi) which don't
    have any effect on control flow can be trivially saved and restored
- ebp can similarly be saved "as is", since its value when
  `setjmp()` executes is exactly what it needs to be restored to in `longjmp()`
- esp cannot be saved "as is" because when `setjmp()` executes, there is the
  extra eip on the stack that is not there after the function returns. Therefore,
  the value for esp that should be saved is esp+4 to match the expected
  state of the stack after return
- The eip that should be saved is the address of the instruction after the
  `call setjmp` instruction, which can be retrieved from the top of the
  stack by dereferencing esp


With all that out of the way, let's read the source (all annotations by me)
([link](http://git.musl-libc.org/cgit/musl/tree/src/setjmp/i386/setjmp.s)).
Since this type of low level register manipulation isn't available from C
(modulo compiler intrinsics), both of these functions are necessarily written
in assembly.


```asm
setjmp:
    mov 4(%esp), %eax     ; get pointer to jmp_buf, passed as argument on stack
    mov    %ebx, (%eax)   ; jmp_buf[0] = ebx
    mov    %esi, 4(%eax)  ; jmp_buf[1] = esi
    mov    %edi, 8(%eax)  ; jmp_buf[2] = edi
    mov    %ebp, 12(%eax) ; jmp_buf[3] = ebp
    lea 4(%esp), %ecx     ; get previous value of esp, before call
    mov    %ecx, 16(%eax) ; jmp_buf[4] = esp before call
    mov  (%esp), %ecx     ; get saved caller eip from top of stack
    mov    %ecx, 20(%eax) ; jmp_buf[5] = saved eip
    xor    %eax, %eax     ; eax = 0
    ret                   ; pop stack into eip
```

The first line retrieves the argument off the stack, placing a pointer to
the `jmp_buf` (remember, an array of 6 unsigned longs) in eax. It then moves
ebx, esi,
edi, and ebp "as is" into the int array. It adds 4 to esp with a `lea` and
stores that next. Next, it dereferences esp and stores that in the last slot
in the array. Lastly, it zeroes out eax and returns.

The final state of the `jmp_buf` after `setjmp()` returns looks like:

```
   0    1    2    3    4    5
[ ebx, esi, edi, ebp, esp, eip ]
```

Now let's look at `longjmp()` ([link](http://git.musl-libc.org/cgit/musl/tree/src/setjmp/i386/longjmp.s)).


```asm
longjmp:
    mov  4(%esp),%edx ; get pointer to jmp_buf, passed as argument 1 on stack
    mov  8(%esp),%eax ; get int val in eax, passed as argument 2 on stack
    test    %eax,%eax ; is int val == 0?
    jnz 1f
    inc     %eax      ; if so, eax++
1:
    mov   (%edx),%ebx ; ebx = jmp_buf[0]
    mov  4(%edx),%esi ; esi = jmp_buf[1]
    mov  8(%edx),%edi ; edi = jmp_buf[2]
    mov 12(%edx),%ebp ; ebp = jmp_buf[3]
    mov 16(%edx),%ecx ; ecx = jmp_buf[4]
    mov     %ecx,%esp ; esp = ecx
    mov 20(%edx),%ecx ; ecx = jmp_buf[5]
    jmp *%ecx         ; eip = ecx
```

The first two lines retrieve the arguments (pointer to `jmp_buf`, int return
val) from the stack into edx and eax, respectively. The int val is
incremented to 1 if it is 0, according to the spec. Next, ebx, esi, edi, and
ebp are reset
to their saved state, stored in the `jmp_buf`, in a straightforward manner.
As you can see, both `setjmp()` and `longjmp()` need to precisely agree on
where each particular register is saved in the `jmp_buf`.
esp is mysteriously restored in an indirect manner, via ecx[^3] and
finally, eip is reset to the saved state via an indirect jump.

So I was mostly correct, but it seems like eax, ecx, and edx were not saved
in the `jmp_buf`!
If we look back on the details of cdecl, it becomes clear why.

- eax doesn't need to be saved, because it is reserved for the return value
- ecx and edx are **caller saved**. This means that a callee subroutine is
  free to trash these registers, and it is the responsibility for the caller
  to save and restore them after the subroutine returns. Because of this,
  if the function that calls `setjmp()` needs to use ecx or edx after the
  call, it will **already** have code to save and restore those registers before
  and after the function call. Since `longjmp()` resumes execution as if
  `setjmp()` had immediately returned, execution will automatically hit the
  code that restores ecx and edx, making it unnecessary to save them in the
  `jmp_buf`.

This is just one example of how great musl libc is at providing an
*understandable* resource for learning the internals of systems software. I
often find myself referencing it when I'm curious about libc internals, and
if you're not familiar with it, I highly recommend checking it out!

[^1]: Mainly, that the function which called `setjmp()` cannot have returned before the corresponding `longjmp()` call.
[^2]: A slight aside: This situation where a function returns different values based on the execution context also appears in `fork()`, in which the caller uses the return value to differentiate whether it is now executing in the child or parent process.  
[^3]: I actually have no good explanation for this and am pretty curious why it's done this way. Something like `mov $esp, [$edx+16]` is a perfectly valid instruction (tested with `rasm2`)! I asked on the musl [mailing list](http://www.openwall.com/lists/musl/2016/01/12/11), but no one responded :(. If you have an explanation, please let me know!
