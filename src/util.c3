module util;

macro void @swap_ptrs(#x, #y) {
	var temp = *#x;
	*#x = *#y;
	*#y = temp;
}

macro @perf(String name = "Current Test"; @body) {
	time::Time start = time::now();
	defer {
		time::Duration dur = time::now() - start;
		io::printfn("Duration of %s: %d", name, dur);
	}
	@body();
}

fn bool nullterm_str_eq(CChar* s1, CChar* s2) {
	assert(s1 != null && s2 != null);

	CChar* s1_p = s1;
	CChar* s2_p = s2;

	while ((*s1_p != '\0') && (*s2_p != '\0') && (*s1_p == *s2_p))
	{
		++s1_p;
		++s2_p;
	}

	return (*s1_p == '\0') && (*s2_p == '\0');
}

fn String nullterm_str_to_slice(CChar* s) {
	assert(s != null);

	usz i = 0;

	while (s[i] != '\0') {
		++i;
	}

	return (String)s[0:(i-1)];
}
