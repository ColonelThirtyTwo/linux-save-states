BITS 64

%define SYS_getpid 39
%define SYS_kill 62

%define SIGTRAP 5
%define SIGABRT 6

EXTERN _lss_one_command
GLOBAL lss_pause:function (lss_pause.end - lss_pause)

SECTION .text
lss_pause: ; void lss_pause(void);
	; get our PID
	mov rax, SYS_getpid
	syscall
	
	; send ourself SIGTRAP so that tracer can catch it
	mov rdi, rax
	mov rsi, SIGTRAP
	mov rax, SYS_kill
	syscall
	
	; run a command
	call _lss_one_command wrt ..plt
	; repeat
	cmp rax, 0
	je lss_pause
	
	ret
.end:
