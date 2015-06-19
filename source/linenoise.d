/// liblinenoies definitions
module linenoise;

version(LineNoise) {}
else static assert("linenoise imported in non-linenoise build");

extern (C) nothrow {
	struct linenoiseCompletions {
		size_t len;
		char **cvec;
	};
	
	alias linenoiseCompletionCallback = void function(const(char) *, linenoiseCompletions *);
	void linenoiseSetCompletionCallback(linenoiseCompletionCallback);
	void linenoiseAddCompletion(linenoiseCompletions *, const(char) *);
	
	char *linenoise(const(char) *prompt);
	int linenoiseHistoryAdd(const(char) *line);
	int linenoiseHistorySetMaxLen(int len);
	int linenoiseHistorySave(const(char) *filename);
	int linenoiseHistoryLoad(const(char) *filename);
	void linenoiseClearScreen();
	void linenoiseSetMultiLine(int ml);
	void linenoisePrintKeyCodes();
}
