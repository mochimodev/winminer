#include <Windows.h>
#include "helpers.h"


int64_t timediff(SYSTEMTIME t1, SYSTEMTIME t2) {
	FILETIME ft1, ft2;
	SystemTimeToFileTime(&t1, &ft1);
	SystemTimeToFileTime(&t2, &ft2);
	ULARGE_INTEGER *u1, *u2;
	u1 = (ULARGE_INTEGER*)&ft1;
	u2 = (ULARGE_INTEGER*)&ft2;
	return u2->QuadPart - u1->QuadPart;
}

int64_t timestamp_ms() {
	SYSTEMTIME t1;
	GetSystemTime(&t1);
	FILETIME ft1;
	SystemTimeToFileTime(&t1, &ft1);
	ULARGE_INTEGER *u1 = (ULARGE_INTEGER*)&ft1;
	// FILETIME is in 100ns intervals, divide by 10000 to get milliseconds.
	return u1->QuadPart / 10000;
}